{ edge, ... }:
{
  services.journald.storage = "persistent";

  services.alloy = {
    enable = true;

    extraFlags = [
      "--server.http.listen-addr=127.0.0.1:12345"
      "--disable-reporting"
    ];
  };

  environment.etc."alloy/config.alloy".text = ''
    // Journal fields arrive as __journal_* and are dropped unless promoted.
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

      // Not job="systemd-journal" — that is the in-cluster DaemonSet's label.
      labels = {
        job  = "edge-journal",
        host = "${edge.instance.hostname}",
      }

      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "http://loki:3100/loki/api/v1/push"
      }
    }
  '';
}
