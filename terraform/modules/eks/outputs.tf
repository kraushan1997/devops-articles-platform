output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "lb_controller_role_arn" {
  value = module.lb_controller_irsa.arn
}

output "karpenter_queue_name" {
  value = module.karpenter.queue_name
}

output "karpenter_node_role_name" {
  value = module.karpenter.node_iam_role_name
}

output "karpenter_service_account" {
  value = module.karpenter.service_account
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
