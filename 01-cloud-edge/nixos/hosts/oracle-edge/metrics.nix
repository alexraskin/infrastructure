{ ... }:
{
  # Scraped over the tailnet via apps/base/monitoring/egress.yaml; eth0 keeps 9100 closed.
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
  };
}
