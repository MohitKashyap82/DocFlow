data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker_lambda" {
  name               = "complyflow-worker-lambda-role"
  description        = "Allows Lambda functions to call AWS services on your behalf."
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

locals {
  worker_lambda_managed_policies = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
  ]
}

resource "aws_iam_role_policy_attachment" "worker_lambda" {
  for_each   = toset(local.worker_lambda_managed_policies)
  role       = aws_iam_role.worker_lambda.name
  policy_arn = each.value
}
