terraform {
  required_version = ">= 1.10"

  required_providers {
    aws     = { source = "hashicorp/aws", version = ">= 6.59, < 7.0" }
    helm    = { source = "hashicorp/helm", version = "~> 3.3" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
  }

  # Remote state with native S3 locking (Terraform >= 1.10). Create the bucket
  # once, then uncomment:
  # backend "s3" {
  #   bucket       = "<your-tf-state-bucket>"
  #   key          = "articles-platform/aws/1-cluster.tfstate"
  #   region       = "ap-south-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region
}

# helm/kubectl authenticate with short-lived tokens from `aws eks get-token`
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}
