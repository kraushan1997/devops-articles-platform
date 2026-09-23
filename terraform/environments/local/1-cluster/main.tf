# Layer 1: the k3d cluster itself (3 servers / HA etcd + 3 zone-labelled agents).
# Kept in its own state so in-cluster resources (layer 2) can be torn down and
# re-applied without touching the cluster, and so the kubernetes/helm providers
# in layer 2 always have a real kubeconfig at plan time.

terraform {
  required_version = ">= 1.10"
  # Local state is fine for a laptop cluster. See environments/aws for S3 state.
}

module "k3d" {
  source = "../../../modules/k3d-cluster"

  cluster_name = var.cluster_name
  servers      = 3
  agents       = 3
}

variable "cluster_name" {
  type    = string
  default = "articles"
}

output "kube_context" {
  value = module.k3d.kube_context
}

output "ingress_url" {
  value = module.k3d.ingress_url
}
