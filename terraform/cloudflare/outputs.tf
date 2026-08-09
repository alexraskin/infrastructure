output "tunnel_id" {
  description = "UUID of the tunnel"
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_cname" {
  description = "What every public hostname CNAMEs to"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
}

output "hostnames" {
  description = "Public hostname -> origin the tunnel forwards it to"
  value       = { for rule in var.ingress : rule.hostname => rule.service }
}

output "tunnel_token" {
  description = "Connector token — the TUNNEL_TOKEN cloudflared runs with"
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive   = true
}
