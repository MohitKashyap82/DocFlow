# Same state bucket/lock table as backbone (provisioned once by infra/bootstrap),
# separate key so the two stacks have independent state and lifecycle.
terraform {
  backend "s3" {
    bucket         = "complyflow-tf-state-261161414394-us-east-1"
    key            = "compute/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "complyflow-tf-locks"
    encrypt        = true
  }
}
