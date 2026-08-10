{ lib, edge, ... }:
{
  systemd.tmpfiles.rules = [
    "d /etc/cloudflare 0700 root root -"
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = edge.acme_email;

    certs = lib.listToAttrs (
      map (
        site:
        lib.nameValuePair site.domain {
          domain = site.domain;
          dnsProvider = "cloudflare";
          environmentFile = "/etc/cloudflare/credentials";

          group = "haproxy";
          reloadServices = [ "haproxy.service" ];
        }
      ) edge.sites
    );
  };

  users.groups.haproxy = { };
}
