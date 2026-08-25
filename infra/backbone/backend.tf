# Provisioned once by infra/bootstrap (applied locally, never from CI).
terraform {
  backend "s3" {
    bucket         = "complyflow-tf-state-261161414394-us-east-1"
    key            = "backbone/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "complyflow-tf-locks"
    encrypt        = true
  }
}
