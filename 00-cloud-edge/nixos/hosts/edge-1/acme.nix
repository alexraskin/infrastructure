{ lib, edge, ... }:
{
  systemd.tmpfiles.rules = [
    "d /etc/cloudflare 0700 root root -"
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = edge.acme_email;

    certs = lib.genAttrs edge.certNames (name: {
      domain = if builtins.elem name edge.wildcards then "*.${name}" else name;
      dnsProvider = "cloudflare";
      environmentFile = "/etc/cloudflare/credentials";

      group = "haproxy";
      reloadServices = [ "haproxy.service" ];
    });
  };

  users.groups.haproxy = { };
}
