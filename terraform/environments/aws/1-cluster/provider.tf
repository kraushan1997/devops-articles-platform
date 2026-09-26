terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }

  # Remote state: S3 with native lockfile locking (Terraform >= 1.10, no DynamoDB).
  # scripts/deploy-aws.sh writes it as backend_override.tf (git-ignored) so the
  # bucket name is not hard-coded here:
  #   backend "s3" {
  #     bucket       = "<your-tf-state-bucket>"
  #     key          = "articles-platform/aws/1-cluster.tfstate"
  #     region       = "us-east-1"
  #     encrypt      = true
  #     use_lockfile = true
  #   }
}

# Credentials are NOT set here. Terraform reads them from the standard AWS chain:
#   aws configure            (~/.aws/credentials, optionally with AWS_PROFILE)
#   or env vars AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
#   or SSO:  aws sso login --profile <name>
# Never commit access keys to .tf files.
provider "aws" {
  region = var.aws_region

  # every AWS resource gets these tags automatically
  default_tags {
    tags = var.tags
  }
}

# helm talks to the new cluster using a short-lived token from the AWS CLI
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", var.aws_region]
    }
  }
}


data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
