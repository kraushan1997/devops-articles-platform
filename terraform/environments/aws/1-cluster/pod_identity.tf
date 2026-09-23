# IAM roles for Kubernetes service accounts, via EKS Pod Identity.
# Each controller gets only the AWS permissions it needs, instead of every pod
# inheriting the node role. (Pod Identity is the newer, simpler alternative to
# IRSA: no OIDC trust policy per role, one trust principal for all.)

locals {
  pod_identity_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# ------------------------------------------------------------------ EBS CSI driver

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.eks_cluster_name}-ebs-csi"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}

# ------------------------------------------------------------------ AWS Load Balancer Controller
# Official policy for the controller version installed in k8s_addons.tf, copied from
# github.com/kubernetes-sigs/aws-load-balancer-controller/docs/install/iam_policy.json

resource "aws_iam_policy" "lb_controller" {
  name   = "${var.eks_cluster_name}-aws-load-balancer-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.eks_cluster_name}-aws-load-balancer-controller"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  policy_arn = aws_iam_policy.lb_controller.arn
  role       = aws_iam_role.lb_controller.name
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}
