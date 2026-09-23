variable "cluster_name" {
  description = "k3d cluster name (kube context becomes k3d-<name>)"
  type        = string
  default     = "articles"
}

variable "servers" {
  description = "Control-plane nodes. 3 = HA embedded etcd (no single control-plane SPOF); must be odd."
  type        = number
  default     = 3
  validation {
    condition     = var.servers % 2 == 1
    error_message = "servers must be an odd number for etcd quorum."
  }
}

variable "agents" {
  description = "Worker nodes. >= 3 so the 3 MongoDB members (hard anti-affinity) each get their own node."
  type        = number
  default     = 3
  validation {
    condition     = var.agents >= 3
    error_message = "At least 3 agents are required for the MongoDB replica set anti-affinity."
  }
}

variable "k3s_image" {
  description = "k3s node image"
  type        = string
  default     = "rancher/k3s:v1.35.8-k3s1"
}

variable "api_port" {
  type    = number
  default = 6550
}

variable "http_port" {
  description = "Host port mapped to the ingress controller (http://localhost:<port>)"
  type        = number
  default     = 8080
}

variable "https_port" {
  type    = number
  default = 8443
}
