/**
 * eks
 * ---
 * AWS resources for a production-shaped EKS cluster:
 *
 *   networking   VPC across 3 AZs, public subnets (ALBs) + private subnets
 *                (nodes, pods), one NAT gateway per AZ (no NAT SPOF)
 *   cluster      EKS control plane (AWS-managed, multi-AZ), secrets envelope
 *                encryption with KMS, control-plane logs to CloudWatch
 *   nodes        a small managed node group across 3 AZs for system workloads
 *                (CoreDNS, Karpenter, Argo CD); application capacity comes from
 *                Karpenter
 *   IAM          IRSA roles for the AWS Load Balancer Controller and EBS CSI
 *                driver, Karpenter controller (Pod Identity) + node role, SQS
 *                interruption queue
 *   registry     ECR repositories (optional; CI pushes to GHCR by default)
 *
 * Built on the community terraform-aws-modules, pinned to major versions.
 */

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = merge(var.tags, {
    Project     = "articles-platform"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ------------------------------------------------------------------ networking
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.cluster_name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]      # /20 each
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 48)] # /24 each

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway # false = one per AZ (HA), true = cheaper
  one_nat_gateway_per_az = !var.single_nat_gateway
  enable_dns_hostnames   = true

  # Subnet discovery for the AWS Load Balancer Controller and Karpenter
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = local.tags
}

# ------------------------------------------------------------------ cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Public endpoint restricted to the given CIDRs; private endpoint for nodes
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs
  endpoint_private_access      = true

  # Whoever runs terraform gets cluster-admin via an EKS access entry
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API"

  # KMS envelope encryption of Secrets + control-plane audit logs
  encryption_config = { resources = ["secrets"] }
  enabled_log_types = ["api", "audit", "authenticator"]

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      # enforce Kubernetes NetworkPolicy natively with the VPC CNI
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.arn
    }
    metrics-server = { most_recent = true }
  }

  eks_managed_node_groups = {
    # Static "system" capacity, one node per AZ minimum. Karpenter itself must not
    # run on Karpenter-managed nodes, so this group is required.
    system = {
      ami_type       = "AL2023_x86_64_STANDARD" # EKS-optimised image: chrony + Amazon Time Sync preconfigured
      instance_types = var.system_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = 3
      max_size     = 6
      desired_size = 3

      labels = { "node-role" = "system" }

      # IMDSv2 only, hop limit 1 -> pods cannot steal the node's IAM credentials
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 50
            volume_type = "gp3"
            encrypted   = true
          }
        }
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.tags
}

# ------------------------------------------------------------------ IRSA roles
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                  = "${var.cluster_name}-ebs-csi"
  use_name_prefix       = false
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                                   = "${var.cluster_name}-aws-lb-controller"
  use_name_prefix                        = false
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
  tags = local.tags
}

# ------------------------------------------------------------------ Karpenter
# Controller IAM role (EKS Pod Identity), node IAM role + instance profile access
# entry, and the SQS queue + EventBridge rules for spot interruption handling.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.26"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true
  namespace                       = "kube-system"
  service_account                 = "karpenter"

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# ------------------------------------------------------------------ registry
resource "aws_ecr_repository" "this" {
  for_each = var.create_ecr ? toset(var.ecr_repositories) : toset([])

  name                 = each.key
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
  }
  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 30 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}
