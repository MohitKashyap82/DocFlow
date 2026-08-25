data "archive_file" "worker" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/worker.zip"
}

resource "aws_lambda_function" "worker" {
  function_name    = "complyflow-worker"
  role             = aws_iam_role.worker_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  filename         = data.archive_file.worker.output_path
  source_code_hash = data.archive_file.worker.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.events.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn = aws_sqs_queue.processing.arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 10
}

import {
  to = aws_lambda_function.worker
  id = "complyflow-worker"
}

import {
  to = aws_lambda_event_source_mapping.worker
  id = "3c031a4e-87a4-4474-8ef9-fc73aecab5ce"
}
