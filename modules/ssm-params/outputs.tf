output "values" {
  description = "Parameter name => decrypted value"
  value       = { for k, p in aws_ssm_parameter.this : k => p.value }
  sensitive   = true
}

output "read_arns" {
  description = "What GetParameter and GetParametersByPath need to read the group"
  value       = [local.path_arn, "${local.path_arn}/*"]
}
