# ------------------------------------------------------------------ cluster IAM role

resource "aws_iam_role" "cluster" {
  name = "${var.eks_cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# ------------------------------------------------------------------ KMS key for Secrets encryption
# Kubernetes Secrets (e.g. MongoDB passwords) are envelope-encrypted in etcd with this key.

resource "aws_kms_key" "eks" {
  description             = "${var.eks_cluster_name} Kubernetes secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.eks_cluster_name}-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_iam_role_policy" "cluster_kms" {
  name = "kms-secrets-encryption"
  role = aws_iam_role.cluster.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:ListGrants", "kms:DescribeKey"]
      Resource = aws_kms_key.eks.arn
    }]
  })
}

# ------------------------------------------------------------------ control-plane logs

resource "aws_cloudwatch_log_group" "eks" {
  # EKS writes to exactly this name; creating it ourselves lets us set retention
  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = 30
}

# ------------------------------------------------------------------ EKS cluster

resource "aws_eks_cluster" "main" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.eks_version

  access_config {
    authentication_mode                         = "API" # access entries instead of the aws-auth ConfigMap
    bootstrap_cluster_creator_admin_permissions = true  # whoever runs terraform becomes cluster-admin
  }

  vpc_config {
    # control-plane ENIs go in the private subnets only
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true                  # nodes talk to the API inside the VPC
    endpoint_public_access  = true                  # kubectl / terraform from your laptop ...
    public_access_cidrs     = var.api_allowed_cidrs # ... but only from these CIDRs
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # We install vpc-cni / kube-proxy / coredns ourselves as managed add-ons (addons.tf),
  # so they are versioned and upgraded by Terraform instead of being unmanaged.
  bootstrap_self_managed_addons = false

  upgrade_policy {
    support_type = "STANDARD" # avoid the paid extended-support tier
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.eks,
  ]
}

# ------------------------------------------------------------------ OIDC provider
# Not needed for EKS Pod Identity (used below), but kept so IRSA also works for any
# chart that only supports IRSA.

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}
