resource "aws_dynamodb_table" "status" {
  name         = "complyflow-status"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fileId"
  range_key    = "timestamp"

  attribute {
    name = "fileId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}
