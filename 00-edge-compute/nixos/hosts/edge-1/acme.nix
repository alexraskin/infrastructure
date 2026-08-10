# LetsEncrypt certs for every site in edge.json, over DNS-01.
#
# DNS-01 rather than HTTP-01 on purpose: it means port 80 is never open, on a
# box whose only exposed surface is 443. The cost is that the box needs a
# Cloudflare token — scripts/push-secrets.sh writes it to
# /etc/cloudflare/credentials as CLOUDFLARE_DNS_API_TOKEN.
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
