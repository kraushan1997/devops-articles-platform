variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "articles-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "api_allowed_cidrs" {
  description = "Restrict the public API endpoint, e.g. [\"203.0.113.10/32\"]"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "single_nat_gateway" {
  description = "Set true to save cost in a demo account (NAT becomes an AZ SPOF)"
  type        = bool
  default     = false
}

variable "karpenter_chart_version" {
  type    = string
  default = "1.14.1"
}

variable "lb_controller_chart_version" {
  type    = string
  default = "3.5.0"
}
