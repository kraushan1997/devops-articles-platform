output "app_namespace" {
  value = var.app_namespace
}

output "mongodb_secret_name" {
  value = kubernetes_secret_v1.mongodb_auth.metadata[0].name
}

output "argocd_admin_password_cmd" {
  description = "Command to read the initial Argo CD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}
