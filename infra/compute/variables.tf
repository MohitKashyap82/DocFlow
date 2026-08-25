variable "aws_region" {
  description = "AWS region for all ComplyFlow resources"
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Tag of the complyflow-api ECR image to deploy"
  type        = string
  default     = "latest"
}
