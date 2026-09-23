module "eks" {
  source = "../../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  api_allowed_cidrs  = var.api_allowed_cidrs
  single_nat_gateway = var.single_nat_gateway
  environment        = "aws"
}
