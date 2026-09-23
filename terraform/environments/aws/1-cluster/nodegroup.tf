# Static "system" node group: one node per AZ minimum, runs CoreDNS, Karpenter,
# the AWS Load Balancer Controller and Argo CD. Application capacity beyond this
# is added on demand by Karpenter (karpenter.tf).

resource "aws_iam_role" "node_role" {
  name = "${var.eks_cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "node_role_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_role_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_role_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_role.name
}

# lets you open a shell on a node with SSM Session Manager instead of SSH + port 22
resource "aws_iam_role_policy_attachment" "node_role_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_role.name
}

# Launch template: only the settings the node group API does not expose directly.
resource "aws_launch_template" "node" {
  name_prefix = "${var.eks_cluster_name}-system-"

  # IMDSv2 only, hop limit 1: pods cannot reach the instance metadata service and
  # steal the node's IAM credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.eks_cluster_name}-system" })
  }
}

resource "aws_eks_node_group" "system" {
  # reference the cluster resource (not the variable) so Terraform waits for the cluster
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = aws_subnet.private[*].id # spread across all AZs

  # EKS-optimised Amazon Linux 2023: chrony + Amazon Time Sync preconfigured
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.node_group_size.desired
    max_size     = var.node_group_size.max
    min_size     = var.node_group_size.min
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "node-role" = "system"
  }

  # desired_size is changed at runtime by autoscaling; don't fight it on every apply
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.node_role_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_role_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_role_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_addon.before_nodes,
  ]
}
