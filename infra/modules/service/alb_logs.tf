data "aws_elb_service_account" "current" {}

# checkov:skip=CKV2_AWS_62: Write-only ALB access log sink; no consumer reads from this bucket so event notifications serve no purpose.
# checkov:skip=CKV_AWS_144: Cross-region replication of access logs is DR-class overhead not warranted for a reference app's log sink.
# checkov:skip=CKV_AWS_18: This bucket IS the ALB access-log destination; enabling S3 server access logging to itself creates an infinite loop.
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.current.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/${var.name_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}
