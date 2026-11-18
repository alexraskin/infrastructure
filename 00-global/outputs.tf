output "ci_role_arns" {
  description = "AWS_ROLE_ARN for each GitHub environment"
  value       = { for k, m in module.ci_role : k => m.role_arn }
}

output "name_servers" {
  description = "Set these at the registrar to cut the domain over to Route 53"
  value       = aws_route53_zone.this.name_servers
}
