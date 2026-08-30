resource "aws_ecr_repository" "app" {
  name                 = var.name_prefix
  image_tag_mutability = "IMMUTABLE"

  # force_delete = true lets terraform destroy clean up the repo even when
  # images are still present. Without this, the first destroy fails because
  # ECR refuses to delete a non-empty repo and the operator has to run
  # `aws ecr batch-delete-image` by hand. Acceptable for a personal demo
  # repo; in a real production setup you'd leave this false to prevent
  # accidental teardown of production images.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  # ECR encrypts every image at rest. This cost-bounded lab uses the AWS-owned
  # AES-256 key; the customer-managed KMS exception is documented separately.
  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ECR lifecycle policies are JSON-only in the AWS API. There is no
# aws_iam_policy_document equivalent (this isn't an IAM policy).
# jsonencode is the documented exception.
#
# Rule priority matters: priority 1 cleans untagged first; priority 2
# then keeps only the last 10 of whatever's left (which is tagged-only
# by that point).
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
