resource "aws_sns_topic" "events" {
  name = "complyflow-events"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "audit_log" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.audit_log.arn
}
