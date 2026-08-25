variable "aws_region" {
  description = "AWS region for all ComplyFlow resources"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address subscribed to the complyflow-events SNS topic"
  type        = string
  default     = "mohitkashyap2003@gmail.com"
}
