# Layer 1: the k3d cluster itself (1 server + 3 zone-labelled agents by default).
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
  servers      = var.servers
  agents       = 3
}

variable "servers" {
  description = <<-EOT
    Control-plane nodes. Default 1: multi-server (embedded etcd) k3d clusters on
    Docker Desktop often lose etcd quorum after a Docker/Windows restart because
    the node containers get new IPs. Set 3 for an HA control plane on a machine
    that stays up (terraform apply -var servers=3). The EKS stack has a
    multi-AZ managed control plane either way.
  EOT
  type        = number
  default     = 1
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
