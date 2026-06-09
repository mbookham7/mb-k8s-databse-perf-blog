terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Networking from 00-vpc, WEKA backend SG from 10-weka-backend.
data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = "../00-vpc/terraform.tfstate"
  }
}

data "terraform_remote_state" "weka_backend" {
  backend = "local"
  config = {
    path = "../10-weka-backend/terraform.tfstate"
  }
}

locals {
  # EKS control plane spans both private subnets (multi-AZ requirement).
  cluster_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  # Backend SGs let WEKA client containers reach the storage cluster
  # (port 14000 + the DPDK port range).
  backend_sg_ids = try(data.terraform_remote_state.weka_backend.outputs.backend_sg_ids, [])

  # Pin the WEKA client node group to AZ-a (same placement group as the backend).
  # Other node groups (system) keep their declared/default subnets.
  az_a_subnet = data.terraform_remote_state.vpc.outputs.backend_subnet_id
  node_groups = {
    for k, v in var.node_groups :
    k => k == "clients" ? merge(v, { subnet_ids = [local.az_a_subnet] }) : v
  }
}

module "eks" {
  source = "../modules/eks"

  region       = var.region
  cluster_name = var.cluster_name
  subnet_ids   = local.cluster_subnet_ids

  kubernetes_version      = var.kubernetes_version
  endpoint_private_access = var.endpoint_private_access
  endpoint_public_access  = var.endpoint_public_access
  public_access_cidrs     = var.public_access_cidrs

  additional_security_group_ids = concat(var.additional_security_group_ids, local.backend_sg_ids)
  authentication_mode           = var.authentication_mode
  enabled_cluster_log_types     = var.enabled_cluster_log_types

  node_groups = local.node_groups

  key_pair_name                = var.key_pair_name
  cpu_manager_reconcile_period = var.cpu_manager_reconcile_period
  cluster_dns_ip               = var.cluster_dns_ip
  enable_cluster_autoscaler    = var.enable_cluster_autoscaler

  enable_ssm_access = var.enable_ssm_access
  admin_role_arn    = var.admin_role_arn

  tags = var.tags
}
