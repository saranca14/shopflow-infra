terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket = "shopflow-terraform-state-122610497964"
    key    = "platform/terraform.tfstate"
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
  subnet_ids = data.terraform_remote_state.shared.outputs.platform_subnet_ids
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = "${var.project_name}-platform"
  cluster_version     = var.cluster_version
  vpc_id              = local.vpc_id
  subnet_ids          = local.subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  tags = {
    Project     = var.project_name
    Environment = "platform"
    Cluster     = "${var.project_name}-platform"
  }
}


# =============================================================
# External Secrets Operator (ESO) — IRSA
# =============================================================

# =============================================================
# External Secrets Operator (ESO) — IRSA
# =============================================================

resource "aws_iam_role" "externalsecrets" {
  name = "${var.project_name}-platform-externalsecrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.oidc_provider_url, "https://", "")}:sub" : "system:serviceaccount:external-secrets:external-secrets",
            "${replace(module.eks.oidc_provider_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Project     = var.project_name
    Environment = "platform"
  }
}

resource "aws_iam_policy" "externalsecrets_policy" {
  name        = "${var.project_name}-platform-externalsecrets-policy"
  description = "Policy for External Secrets Operator to read specific secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          data.terraform_remote_state.shared.outputs.github_pat_secret_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "externalsecrets_attach" {
  role       = aws_iam_role.externalsecrets.name
  policy_arn = aws_iam_policy.externalsecrets_policy.arn
}

output "externalsecrets_role_arn" {
  value = aws_iam_role.externalsecrets.arn
}
