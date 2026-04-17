terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket = "shopflow-terraform-state-122610497964"
    key    = "app/terraform.tfstate"
    region = "eu-west-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Read shared infra outputs (VPC, subnets)
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "shopflow-terraform-state-122610497964"
    key    = "shared/terraform.tfstate"
    region = "eu-west-1"
  }
}

locals {
  vpc_id     = data.terraform_remote_state.shared.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.shared.outputs.app_subnet_ids
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = "${var.project_name}-app"
  cluster_version     = var.cluster_version
  vpc_id              = local.vpc_id
  subnet_ids          = local.subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  tags = {
    Project     = var.project_name
    Environment = "app"
    Cluster     = "${var.project_name}-app"
  }
}
