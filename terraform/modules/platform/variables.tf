variable "environment" {
  description = "Selects gitops/apps/<environment> (currently: aws)"
  type        = string
  validation {
    condition     = contains(["aws"], var.environment)
    error_message = "environment must be 'aws'."
  }
}

variable "app_namespace" {
  type    = string
  default = "articles"
}

variable "app_namespace_extra_labels" {
  description = "Extra labels for the app namespace (EKS: ALB pod readiness gate injection)"
  type        = map(string)
  default     = {}
}

variable "gitops_repo_url" {
  description = "Git repository Argo CD watches"
  type        = string
  default     = "https://github.com/kraushan1997/devops-articles-platform.git"
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (argoproj/argo-helm)"
  type        = string
  default     = "9.7.1"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version (argoproj/argo-helm)"
  type        = string
  default     = "2.0.5"
}

variable "argocd_ha" {
  description = "Run Argo CD components with multiple replicas + redis-ha"
  type        = bool
  default     = false
}
