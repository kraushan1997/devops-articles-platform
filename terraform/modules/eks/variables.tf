variable "cluster_name" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheaper, AZ SPOF for egress); false = one NAT per AZ"
  type        = bool
  default     = false
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Restrict to your IP/VPN."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "create_ecr" {
  type    = bool
  default = true
}

variable "ecr_repositories" {
  type    = list(string)
  default = ["articles-api", "mongodb"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
