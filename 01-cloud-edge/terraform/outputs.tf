output "public_ip" {
  description = "Ephemeral public IP. dns.tf already points the site records at it."
  value       = oci_core_instance.edge.public_ip
}

output "private_ip" {
  description = "Address inside the VCN"
  value       = oci_core_instance.edge.private_ip
}

output "instance_id" {
  value = oci_core_instance.edge.id
}

output "availability_domain" {
  description = "Which AD the instance actually landed in, after any capacity retries"
  value       = oci_core_instance.edge.availability_domain
}

output "sites" {
  description = "Public hostname -> home backend, as HAProxy will route them"
  value       = { for site in local.edge.sites : site.domain => site.backend }
}
