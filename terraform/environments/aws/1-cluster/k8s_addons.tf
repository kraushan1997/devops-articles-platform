# In-cluster components that must exist before workloads: default StorageClass and
# the AWS Load Balancer Controller (turns Ingress objects into ALBs).

# Encrypted gp3 as the default StorageClass (MongoDB PVCs). WaitForFirstConsumer
# creates each EBS volume in the AZ where its pod was scheduled; Retain keeps the
# data if a PVC is deleted by mistake.
resource "kubectl_manifest" "gp3_storage_class" {
  yaml_body = <<-YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: gp3
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
    provisioner: ebs.csi.aws.com
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
    reclaimPolicy: Retain
    parameters:
      type: gp3
      encrypted: "true"
  YAML

  depends_on = [aws_eks_addon.ebs_csi]
}

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
