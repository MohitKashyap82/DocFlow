output "tf_state_bucket" {
  value = aws_s3_bucket.tf_state.id
}

output "tf_lock_table" {
  value = aws_dynamodb_table.tf_locks.name
}

output "github_actions_role_arn" {
  description = "Paste this into the GitHub repo's Actions variables as AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
