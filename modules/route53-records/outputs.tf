output "ds_record" {
  description = "The zone's DS record, when dnssec is set"
  value       = one(aws_route53_key_signing_key.this[*].ds_record)
}
