output "user_name" {
  description = "Create its key with: aws iam create-access-key --user-name <this>"
  value       = aws_iam_user.this.name
}
