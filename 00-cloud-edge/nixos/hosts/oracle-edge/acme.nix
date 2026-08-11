{
  config,
  lib,
  edge,
  ...
}:
{
  security.acme = {
    acceptTerms = true;
    defaults.email = edge.acme_email;

    certs = lib.genAttrs edge.certNames (name: {
      domain = if builtins.elem name edge.wildcards then "*.${name}" else name;
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."cloudflare-credentials".path;

      group = "haproxy";
      reloadServices = [ "haproxy.service" ];
    });
  };

  users.groups.haproxy = { };
}
