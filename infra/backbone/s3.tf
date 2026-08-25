locals {
  uploads_bucket_name = "complyflow-uploads-${data.aws_caller_identity.current.account_id}-${var.aws_region}-an"
}

resource "aws_s3_bucket" "uploads" {
  bucket = local.uploads_bucket_name
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Required for the presigned-URL upload flow: the browser PUTs directly to S3
# from whatever origin the API is served on (the ALB), which is cross-origin
# from the bucket's endpoint. Without this, every upload fails a CORS
# preflight in the browser even though it works fine from curl/console.
resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  cors_rule {
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  queue {
    id        = "complyflow-upload-trigger"
    queue_arn = aws_sqs_queue.processing.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.processing]
}

import {
  to = aws_s3_bucket.uploads
  id = "complyflow-uploads-261161414394-us-east-1-an"
}

import {
  to = aws_s3_bucket_versioning.uploads
  id = "complyflow-uploads-261161414394-us-east-1-an"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.uploads
  id = "complyflow-uploads-261161414394-us-east-1-an"
}

import {
  to = aws_s3_bucket_public_access_block.uploads
  id = "complyflow-uploads-261161414394-us-east-1-an"
}

import {
  to = aws_s3_bucket_ownership_controls.uploads
  id = "complyflow-uploads-261161414394-us-east-1-an"
}

import {
  to = aws_s3_bucket_notification.uploads
  id = "complyflow-uploads-261161414394-us-east-1-an"
}
