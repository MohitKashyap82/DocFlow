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

import {
  to = aws_sns_topic.events
  id = "arn:aws:sns:us-east-1:261161414394:complyflow-events"
}

import {
  to = aws_sns_topic_subscription.audit_log
  id = "arn:aws:sns:us-east-1:261161414394:complyflow-events:31df41ed-b137-4e48-bb22-7f121af4ee41"
}

import {
  to = aws_sns_topic_subscription.email_alert
  id = "arn:aws:sns:us-east-1:261161414394:complyflow-events:e2ff7862-453a-4a1c-b675-2e04a8f173cc"
}
