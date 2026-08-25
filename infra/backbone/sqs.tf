resource "aws_sqs_queue" "processing_dlq" {
  name                       = "complyflow-processing-dlq"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true

  # The live queue reports max_message_size=1048576, a legacy value above the
  # provider's current 262144 ceiling that the API still tolerates but won't
  # let Terraform set. Leave it alone rather than shrinking it on apply.
  lifecycle {
    ignore_changes = [max_message_size]
  }
}

resource "aws_sqs_queue" "processing" {
  name                       = "complyflow-processing"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 3
  })

  lifecycle {
    ignore_changes = [max_message_size]
  }
}

resource "aws_sqs_queue" "audit_log" {
  name                       = "complyflow-audit-log"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true

  lifecycle {
    ignore_changes = [max_message_size]
  }
}

data "aws_iam_policy_document" "processing_queue_policy" {
  statement {
    sid       = "__owner_statement"
    effect    = "Allow"
    actions   = ["SQS:*"]
    resources = [aws_sqs_queue.processing.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowS3ToSendMessages"
    effect    = "Allow"
    actions   = ["SQS:SendMessage"]
    resources = [aws_sqs_queue.processing.arn]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.uploads.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "processing" {
  queue_url = aws_sqs_queue.processing.id
  policy    = data.aws_iam_policy_document.processing_queue_policy.json
}

data "aws_iam_policy_document" "audit_log_queue_policy" {
  statement {
    sid       = "__owner_statement"
    effect    = "Allow"
    actions   = ["SQS:*"]
    resources = [aws_sqs_queue.audit_log.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "topic-subscription-${aws_sns_topic.events.arn}"
    effect    = "Allow"
    actions   = ["SQS:SendMessage"]
    resources = [aws_sqs_queue.audit_log.arn]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "audit_log" {
  queue_url = aws_sqs_queue.audit_log.id
  policy    = data.aws_iam_policy_document.audit_log_queue_policy.json
}

import {
  to = aws_sqs_queue.processing_dlq
  id = "https://sqs.us-east-1.amazonaws.com/261161414394/complyflow-processing-dlq"
}

import {
  to = aws_sqs_queue.processing
  id = "https://sqs.us-east-1.amazonaws.com/261161414394/complyflow-processing"
}

import {
  to = aws_sqs_queue.audit_log
  id = "https://sqs.us-east-1.amazonaws.com/261161414394/complyflow-audit-log"
}

import {
  to = aws_sqs_queue_policy.processing
  id = "https://sqs.us-east-1.amazonaws.com/261161414394/complyflow-processing"
}

import {
  to = aws_sqs_queue_policy.audit_log
  id = "https://sqs.us-east-1.amazonaws.com/261161414394/complyflow-audit-log"
}
