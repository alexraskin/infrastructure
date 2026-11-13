output "ci_role_arns" {
  description = "AWS_ROLE_ARN for each GitHub environment"
  value       = { for k, m in module.ci_role : k => m.role_arn }
}
