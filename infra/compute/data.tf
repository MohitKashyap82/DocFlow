data "terraform_remote_state" "backbone" {
  backend = "s3"
  config = {
    bucket = "complyflow-tf-state-261161414394-us-east-1"
    key    = "backbone/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Generic role shared across projects in this account (not ComplyFlow-specific) --
# referenced read-only, never created/modified/destroyed by this stack.
data "aws_iam_role" "ecs_execution" {
  name = "ecsTaskExecutionRole"
}

data "aws_ecr_repository" "api" {
  name = "complyflow-api"
}
