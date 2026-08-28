terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bootstrap has no remote backend to point at yet (it's what CREATES the
  # remote backend). State lives locally and this stack is applied once,
  # by hand, never from CI.
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Terraform remote state: S3 bucket + DynamoDB lock table
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = "complyflow-tf-state-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_locks" {
  name         = "complyflow-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC role
#
# Reuses the OIDC provider already registered in this account (created for
# another project) instead of creating a second one or storing static AWS
# access keys as GitHub secrets.
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_repo_parts = split("/", var.github_repo)
  github_owner      = local.github_repo_parts[0]
  github_repo_name  = local.github_repo_parts[1]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHub's sub claim comes in two shapes depending on context: the classic
    # "repo:owner/repo:..." form, and a newer one embedding immutable numeric
    # IDs -- "repo:owner@ownerId/repo@repoId:..." (anti-spoofing hardening so
    # a deleted-and-recreated repo of the same name can't reuse old tokens).
    # Matching both keeps this working regardless of which GitHub sends.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:*",
        "repo:${local.github_owner}@*/${local.github_repo_name}@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "complyflow-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

data "aws_iam_policy_document" "github_actions_permissions" {
  # Terraform state backend access
  statement {
    sid       = "TerraformStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.tf_state.arn]
  }
  statement {
    sid       = "TerraformStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tf_state.arn}/*"]
  }
  statement {
    sid       = "TerraformLockTable"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tf_locks.arn]
  }

  # ComplyFlow application resources
  statement {
    # Terraform's AWS provider probes many bucket-level settings on every
    # refresh (accelerate config, logging, replication, etc.) regardless of
    # whether this project's config touches them. Enumerating each one is
    # whack-a-mole; s3:* is fine here since the resource scope is already
    # tightly restricted to just this bucket.
    sid    = "ComplyFlowS3"
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      "arn:aws:s3:::complyflow-uploads-*",
      "arn:aws:s3:::complyflow-uploads-*/*",
    ]
  }
  statement {
    sid       = "ComplyFlowDynamoDB"
    effect    = "Allow"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/complyflow-status"]
  }
  statement {
    sid       = "ComplyFlowSQS"
    effect    = "Allow"
    actions   = ["sqs:*"]
    resources = ["arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:complyflow-*"]
  }
  statement {
    sid       = "ComplyFlowLambda"
    effect    = "Allow"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:complyflow-*"]
  }
  statement {
    # Event source mapping ARNs are opaque UUIDs (not tied to the function
    # name), so this can't be scoped down to just complyflow-* the way the
    # statement above is.
    sid    = "ComplyFlowLambdaEventSourceMapping"
    effect = "Allow"
    actions = [
      "lambda:GetEventSourceMapping", "lambda:ListEventSourceMappings",
      "lambda:CreateEventSourceMapping", "lambda:UpdateEventSourceMapping", "lambda:DeleteEventSourceMapping",
      "lambda:ListTags", "lambda:TagResource", "lambda:UntagResource",
    ]
    resources = ["arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:event-source-mapping:*"]
  }
  statement {
    sid       = "ComplyFlowSNS"
    effect    = "Allow"
    actions   = ["sns:*"]
    resources = ["arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:complyflow-*"]
  }
  statement {
    sid    = "ComplyFlowIAM"
    effect = "Allow"
    actions = [
      "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/complyflow-*"]
  }
  statement {
    sid       = "ComplyFlowIAMPolicyRead"
    effect    = "Allow"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = ["arn:aws:iam::aws:policy/*"]
  }
  statement {
    sid       = "ComplyFlowIAMReadExecutionRole"
    effect    = "Allow"
    actions   = ["iam:GetRole", "iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"]
  }
  statement {
    sid    = "ComplyFlowECR"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "ComplyFlowECRRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
      "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:ListTagsForResource",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/complyflow-api"]
  }
  statement {
    sid    = "ComplyFlowLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy", "logs:TagResource", "logs:ListTagsForResource",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/complyflow*"]
  }
  statement {
    # DescribeLogGroups is a listing call that doesn't scope cleanly to one
    # log group's ARN -- AWS evaluates it against a generic log-group/
    # log-stream resource shape rather than a specific name, so this needs
    # account-wide resource scope even though the action itself is read-only.
    sid       = "ComplyFlowLogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  # ECS, ELBv2, and the EC2 security-group/VPC-describe actions needed for the
  # compute stack don't support meaningful resource-level scoping for these
  # verbs, so this mirrors the project's documented "full access on this
  # service, scoped down later" pattern (see complyflow-console-setup.md Phase 5).
  statement {
    sid    = "ComplyFlowComputeWildcardServices"
    effect = "Allow"
    actions = [
      "ecs:*", "elasticloadbalancing:*", "ec2:Describe*", "ec2:*SecurityGroup*", "ec2:CreateTags",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "STSIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "complyflow-github-actions-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
