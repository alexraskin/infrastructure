output "fqdns" {
  description = "Key => FQDN"
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}
