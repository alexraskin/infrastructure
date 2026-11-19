output "trail_arn" {
  description = "ARN of the trail"
  value       = aws_cloudtrail.this.arn
}

output "bucket" {
  description = "Bucket the logs land in"
  value       = aws_s3_bucket.this.id
}
