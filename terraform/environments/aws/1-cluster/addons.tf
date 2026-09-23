# EKS managed add-ons. Versions default to the latest one compatible with the
# cluster version (looked up with aws_eks_addon_version).

locals {
  # networking must exist before nodes join, otherwise they never become Ready
  addons_before_nodes = {
    vpc-cni = {
      # enforce Kubernetes NetworkPolicy objects natively
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    kube-proxy             = {}
    eks-pod-identity-agent = {}
  }

  # these need running nodes to schedule their pods
  addons_after_nodes = {
    coredns        = {}
    metrics-server = {} # required by the HorizontalPodAutoscaler
  }
}

data "aws_eks_addon_version" "this" {
  for_each = merge(local.addons_before_nodes, local.addons_after_nodes, { aws-ebs-csi-driver = {} })

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "before_nodes" {
  for_each = local.addons_before_nodes

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  configuration_values        = lookup(each.value, "configuration_values", null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "after_nodes" {
  for_each = local.addons_after_nodes

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.system]
}

# EBS CSI driver: provisions the gp3 volumes for MongoDB. Gets AWS permissions
# through EKS Pod Identity (pod_identity.tf).
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.this["aws-ebs-csi-driver"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  depends_on = [aws_eks_node_group.system, aws_eks_addon.before_nodes]
}
