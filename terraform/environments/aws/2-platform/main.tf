# Layer 2 (AWS): Kubernetes-side bootstrap, applied after layer 1 has created the cluster.
# Argo CD + root app (pointed at gitops/apps/aws), namespaces, secrets, StorageClass, Karpenter pools.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.2" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    random     = { source = "hashicorp/random", version = "~> 3.9" }
  }
  # backend "s3" { key = "articles-platform/aws/2-platform.tfstate" ... }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "eks_cluster_name" {
  type    = string
  default = "articles-eks"
}

variable "gitops_repo_url" {
  type    = string
  default = "https://github.com/kraushan1997/devops-articles-platform.git"
}

# credentials come from `aws configure` / AWS_PROFILE - never hard-code keys here
provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

locals {
  exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name, "--region", var.aws_region]
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = local.exec.api_version
    command     = local.exec.command
    args        = local.exec.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec                   = local.exec
  }
}

module "platform" {
  source = "../../../modules/platform"

  environment     = "aws"
  gitops_repo_url = var.gitops_repo_url
  argocd_ha       = true

  # ALB controller injects readiness gates: a pod only counts as Ready once the
  # ALB target group reports it healthy -> zero-downtime rolling updates
  app_namespace_extra_labels = { "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled" }

  # MongoDB PVCs need the gp3 StorageClass before Argo CD deploys them
  depends_on = [kubernetes_storage_class_v1.gp3]
}

output "argocd_admin_password_cmd" {
  value = module.platform.argocd_admin_password_cmd
}

output "api_endpoint_cmd" {
  value = "kubectl -n articles get ingress articles-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "grafana_admin_password" {
  value     = module.platform.grafana_admin_password
  sensitive = true
}
