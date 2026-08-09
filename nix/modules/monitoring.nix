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

  # Nothing else is needed for Grafana: it is a ClusterIP behind a tailscale
  # operator Ingress, so the proxy pod dials out to the tailnet from inside the
  # cluster and no node port is involved at all.
}
