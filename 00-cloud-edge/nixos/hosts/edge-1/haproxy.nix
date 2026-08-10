{
  lib,
  edge,
  ...
}:
let
  # HAProxy selects among several certs by SNI, so one bind line lists them all.
  # Keyed on cert names, not sites: several sites can share one wildcard.
  certs = lib.concatMapStringsSep " " (name: "crt /var/lib/acme/${name}/full.pem") edge.certNames;

  routes = lib.concatMapStringsSep "\n" (
    site: "    use_backend ${site.name} if { hdr(host) -i ${site.domain} }"
  ) sites;

  backends = lib.concatMapStringsSep "\n" (site: ''
    backend ${site.name}
      mode http
      server ${site.name} ${site.backend} check inter 10s
  '') sites;

  # HAProxy identifiers cannot contain dots.
  sites = map (site: site // { name = lib.replaceStrings [ "." ] [ "_" ] site.domain; }) edge.sites;
in
{
  systemd.services.haproxy = {
    after = map (name: "acme-finished-${name}.target") edge.certNames;
    wants = map (name: "acme-finished-${name}.target") edge.certNames;
  };

  services.haproxy = {
    enable = true;
    config = ''
      global
        log /dev/log local0 info
        maxconn 2000

      defaults
        log global
        mode http
        option httplog
        option dontlognull
        # Streams are long and mostly idle between range requests, and Plex
        # holds a websocket open for its event channel. The defaults (1m
        # client/server, no tunnel setting) cut both.
        timeout connect 5s
        timeout client  5m
        timeout server  5m
        timeout tunnel  4h

      frontend https_in
        bind :443 ssl ${certs} alpn h2,http/1.1
        option forwardfor
        http-request set-header X-Real-IP %[src]
        http-request set-header X-Forwarded-Proto https
        http-request set-header X-Forwarded-Port 443

      ${routes}

        default_backend unknown_host

      ${backends}

      # A hostname that resolves here but has no rule must not fall through to
      # a real backend. Same intent as the tunnel's http_status:404 catch-all.
      backend unknown_host
        http-request deny status 404
    '';
  };
}
