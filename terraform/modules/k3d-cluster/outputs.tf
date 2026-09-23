output "cluster_name" {
  value = var.cluster_name
}

output "kube_context" {
  description = "kubeconfig context written to ~/.kube/config"
  value       = "k3d-${var.cluster_name}"
  depends_on  = [terraform_data.cluster]
}

output "ingress_url" {
  value = "http://localhost:${var.http_port}"
}
