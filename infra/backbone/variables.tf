variable "aws_region" {
  description = "AWS region for all ComplyFlow resources"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address subscribed to the complyflow-events SNS topic. Supplied at run time (TF_VAR_alert_email locally, a repo variable in CI) rather than defaulted here, so it isn't published in source."
  type        = string
}
