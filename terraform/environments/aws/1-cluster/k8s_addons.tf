# The AWS Load Balancer Controller (turns Ingress objects into ALBs).

# The default gp3 StorageClass is created in layer 2 (aws/2-platform/storage.tf):
# Kubernetes objects need a live cluster at plan time.

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version

  values = [yamlencode({
    clusterName         = aws_eks_cluster.main.name
    region              = var.aws_region
    vpcId               = aws_vpc.main.id
    replicaCount        = 2
    serviceAccount      = { name = "aws-load-balancer-controller" } # matches the pod identity association
    podDisruptionBudget = { maxUnavailable = 1 }
    nodeSelector        = { "node-role" = "system" }
  })]

  depends_on = [
    aws_eks_pod_identity_association.lb_controller,
    aws_iam_role_policy_attachment.lb_controller,
    aws_eks_addon.after_nodes,
  ]
}
