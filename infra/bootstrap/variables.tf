variable "aws_region" {
  description = "AWS region for all ComplyFlow resources"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub org/repo allowed to assume the deploy role, as 'owner/repo'"
  type        = string
  default     = "MohitKashyap82/DocFlow"
}
