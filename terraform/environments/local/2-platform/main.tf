# Layer 2: namespaces, MongoDB secret, Argo CD and the root GitOps Application.
# Everything else is deployed by Argo CD from gitops/apps/local.

terraform {
  required_version = ">= 1.10"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.2" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    random     = { source = "hashicorp/random", version = "~> 3.9" }
  }
}

variable "kube_context" {
  description = "Context created by layer 1"
  type        = string
  default     = "k3d-articles"
}

variable "gitops_repo_url" {
  type    = string
  default = "https://github.com/kraushan1997/devops-articles-platform.git"
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

module "platform" {
  source = "../../../modules/platform"

  environment     = "local"
  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  argocd_ha       = false
}

output "argocd_admin_password_cmd" {
  value = module.platform.argocd_admin_password_cmd
}

output "next_steps" {
  value = <<-EOT
    Argo CD is now syncing gitops/apps/local. Watch it with:
      kubectl -n argocd get applications -w
    Argo CD UI:  kubectl -n argocd port-forward svc/argocd-server 8081:80  ->  http://localhost:8081
    API:         http://localhost:8080/articles
  EOT
}

output "grafana_admin_password" {
  value     = module.platform.grafana_admin_password
  sensitive = true
}
