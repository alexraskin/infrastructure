{ edge, ... }:
{
  # HAProxy logs with `log /dev/log local0 info`, and journald owns /dev/log —
  # so haproxy, tailscaled, acme-*.service, sshd and the kernel are all one
  # journal, and one source below picks up all of them. No rsyslog involved.
  #
  # Volatile storage is the default when /var/log/journal does not exist, which
  # would drop everything not yet shipped across a reboot.
  services.journald.storage = "persistent";

  services.alloy = {
    enable = true;

    # The nixpkgs module already puts the unit in the systemd-journal group, so
    # loki.source.journal below can read /var/log/journal without extra wiring.
    #
    # Alloy's own UI/API listens on 0.0.0.0:12345 by default, and
    # `trustedInterfaces = [ "tailscale0" ]` in default.nix means every port is
    # open to every tailnet peer regardless of allowedTCPPorts. Bind it to
    # loopback rather than widen the firewall reasoning.
    extraFlags = [
      "--server.http.listen-addr=127.0.0.1:12345"
      "--disable-reporting"
    ];
  };

  # /etc rather than a store path on purpose: the module wires *.alloy files
  # under /etc/alloy into reloadTriggers, so a config change reloads instead of
  # restarting and re-reading the journal from the cursor.
  environment.etc."alloy/config.alloy".text = ''
    // Journal fields arrive as __journal_*, which Loki drops unless promoted.
    // Without this every line is labelled only by job/host and finding the
    // HAProxy ones means grepping the message body.
    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal_syslog_identifier"]
        target_label  = "syslog_identifier"
      }
    }

    loki.source.journal "host" {
      max_age       = "12h"
      path          = "/var/log/journal"
      relabel_rules = loki.relabel.journal.rules

      // Not job="systemd-journal": that is what the in-cluster Alloy DaemonSet
      // labels the six k3s nodes with, and reusing it would quietly fold an
      // Oracle box into every existing {job="systemd-journal"} query.
      labels = {
        job  = "edge-journal",
        host = "${edge.instance.hostname}",
      }

      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        // A bare MagicDNS name, resolved peer-to-peer over the tailnet.
        // Requires --accept-dns=true in tailscale.nix: that is what installs
        // "search <tailnet>.ts.net" in resolv.conf, and *.ts.net is not
        // published in public DNS, so with it false there is no resolver for
        // this name anywhere on the box.
        //
        // Plain http, and no tailnet name in the URL, both because
        // apps/base/loki/service.yaml serves this as a tailscale LoadBalancer
        // rather than an HTTPS Ingress — an Ingress' cert is issued for the
        // FQDN, so https://loki/ would fail hostname verification and the
        // tailnet name would have to be hidden in edge.json. WireGuard already
        // encrypts the hop; the ACL grant is the access control.
        //
        // Not reachable any other way: this box runs without --accept-routes,
        // and the cluster's advertised 10.0.200.0/24 is node LAN space anyway,
        // so Loki's ClusterIP was never in it.
        url = "http://loki:3100/loki/api/v1/push"
      }
    }
  '';
}
