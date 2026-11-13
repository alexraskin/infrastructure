output "role_arn" {
  description = "What aws-actions/configure-aws-credentials assumes"
  value       = aws_iam_role.this.arn
}
