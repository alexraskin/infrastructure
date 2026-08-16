# The status page as a Tailscale Service: a tailnet name and VIP owned by the
# tailnet, not by whichever proxy pod is advertising it. The ingress ProxyGroup
# in apps/base/tailscale-ingress/ advertises it; the ACL auto-approves that.
resource "tailscale_service" "status" {
  name    = "svc:status"
  comment = "Gatus status page, advertised by the cluster's ingress ProxyGroup"
  ports   = ["tcp:443"]
}
