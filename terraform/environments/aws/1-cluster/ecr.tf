# Container registry. CI pushes to GHCR by default; these repositories are ready
# if you prefer to keep images inside AWS (nodes can already pull from ECR via
# AmazonEC2ContainerRegistryReadOnly).

resource "aws_ecr_repository" "repo" {
  for_each = toset(var.ecr_repositories)

  name                 = each.key
  image_tag_mutability = "IMMUTABLE" # a tag always means the same image
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "repo" {
  for_each   = aws_ecr_repository.repo
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
