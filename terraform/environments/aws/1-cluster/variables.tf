variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones. 3 so a 3-member MongoDB replica set keeps a majority if one AZ fails."
  type        = number
  default     = 3
  validation {
    condition     = var.az_count >= 3
    error_message = "Use at least 3 AZs (MongoDB majority must survive the loss of one AZ)."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway for all AZs (cheaper, but an AZ outage breaks egress). false = one NAT per AZ."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every AWS resource (via provider default_tags)."
  type        = map(string)
  default = {
    terraform = "true"
    project   = "articles-platform"
  }
}

variable "eks_version" {
  description = "The Kubernetes version of the EKS cluster."
  type        = string
  default     = "1.35"
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
  default     = "articles-eks"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Set this to your own IP, e.g. [\"203.0.113.10/32\"]."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the static system node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_group_size" {
  description = "Scaling config of the system node group (one node per AZ minimum)."
  type = object({
    min     = number
    desired = number
    max     = number
  })
  default = { min = 3, desired = 3, max = 6 }
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version."
  type        = string
  default     = "1.14.1"
}

variable "lb_controller_chart_version" {
  description = "aws-load-balancer-controller Helm chart version (keep policies/aws-load-balancer-controller.json in sync)."
  type        = string
  default     = "3.5.0"
}

variable "ecr_repositories" {
  description = "ECR repositories to create (CI pushes to GHCR by default; ECR is ready for an AWS-only setup)."
  type        = list(string)
  default     = ["articles-api", "mongodb"]
}
