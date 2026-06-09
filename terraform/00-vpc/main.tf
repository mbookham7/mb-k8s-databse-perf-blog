terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -----------------------------------------------------------------------------
# Self-contained EC2 key pair: generated here so the demo needs no pre-existing
# key. The private key is written to <this dir>/<cluster_name>-key.pem (0600,
# git-ignored). The WEKA backend layer consumes the name via remote state.
# -----------------------------------------------------------------------------
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${var.cluster_name}-key"
  public_key = tls_private_key.main.public_key_openssh
  tags       = var.tags
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.main.private_key_pem
  filename        = "${path.module}/${var.cluster_name}-key.pem"
  file_permission = "0600"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # AZ-a hosts the WEKA backend placement group + the EKS client node group.
  # AZ-b only exists to satisfy multi-AZ requirements (EKS control plane and
  # the WEKA ALB both need subnets in two AZs).
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # /20 private subnets, /24 public subnets carved from the VPC CIDR.
  private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 48)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Single NAT gateway keeps cost down; backend + nodes are private but need
  # egress for get.weka.io, image pulls, and the EKS/Secrets Manager APIs.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet discovery tags for the in-cluster AWS Load Balancer Controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}
