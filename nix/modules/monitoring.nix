# Host-side holes the in-cluster monitoring stack needs.
#
# Not in the golden image, for the same reason tailscale.nix is not: the image
# has no cluster to be scraped by.
{ ... }:
{
  networking.firewall.allowedTCPPorts = [
    # prometheus-node-exporter runs with hostNetwork on every node. Prometheus
    # scrapes it at <node-ip>:9100, and that packet arrives over flannel, not
    # over loopback — with the port closed every node target sits DOWN and the
    # failure looks like a broken exporter rather than a firewall.
    9100
  ];

  # Grafana's NodePort (30300) is deliberately *not* opened. Access is over the
  # tailnet, where traffic arrives on tailscale0 — a trusted interface, see
  # tailscale.nix. Add 30300 here only to also reach it from the LAN.
}
