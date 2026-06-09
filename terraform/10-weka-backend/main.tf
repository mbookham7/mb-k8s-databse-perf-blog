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

# Pull networking from the 00-vpc layer so subnets never need to be copied by hand.
data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = "../00-vpc/terraform.tfstate"
  }
}

locals {
  # try() so this layer can still be planned/destroyed even if the 00-vpc layer
  # has already been destroyed (its remote-state outputs would then be empty).
  vpc_backend_subnet_id = try(data.terraform_remote_state.vpc.outputs.backend_subnet_id, null)
  vpc_alb_subnet_id     = try(data.terraform_remote_state.vpc.outputs.alb_subnet_id, null)
}

module "weka_backend" {
  source = "../modules/weka-backend"

  cluster_name      = var.cluster_name
  cluster_size      = var.cluster_size
  prefix            = var.prefix
  instance_type     = var.instance_type
  key_pair_name     = coalesce(var.key_pair_name, data.terraform_remote_state.vpc.outputs.key_pair_name)
  assign_public_ip  = var.assign_public_ip
  weka_version      = var.weka_version
  get_weka_io_token = var.get_weka_io_token

  # AZ-a private subnet (single placement group); ALB needs a second AZ.
  subnet_ids         = local.vpc_backend_subnet_id != null ? [local.vpc_backend_subnet_id] : []
  sg_ids             = var.sg_ids
  create_nat_gateway = var.create_nat_gateway

  create_alb               = var.create_alb
  alb_additional_subnet_id = local.vpc_alb_subnet_id

  set_dedicated_fe_container = var.set_dedicated_fe_container
  data_services_number       = var.data_services_number

  tiering_enable_obs_integration = var.tiering_enable_obs_integration
  tiering_obs_name               = var.tiering_obs_name
  tiering_enable_ssd_percent     = var.tiering_enable_ssd_percent

  secretmanager_use_vpc_endpoint    = var.secretmanager_use_vpc_endpoint
  secretmanager_create_vpc_endpoint = var.secretmanager_create_vpc_endpoint

  instance_iam_profile_arn = var.instance_iam_profile_arn
  lambda_iam_role_arn      = var.lambda_iam_role_arn
  sfn_iam_role_arn         = var.sfn_iam_role_arn
  event_iam_role_arn       = var.event_iam_role_arn

  tags_map = var.tags_map
}
