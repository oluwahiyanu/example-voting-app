terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "eu-north-1"
}

variable "cluster_name" {
  default = "capstone-cluster"
}

# Use the default VPC that every AWS account already has
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  # Bypasses the IAM OIDC policy restriction (IRSA) for free/restricted student accounts
  enable_irsa = false

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      min_size       = 2
      max_size       = 4
      desired_size   = 4
    }
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}