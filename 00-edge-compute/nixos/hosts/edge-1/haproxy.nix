# HAProxy: terminate TLS on the public IP, forward to home over the tailnet.
#
# The reference design this is modelled on SNI-passthroughs to a proxy at home
# that owns the certs. That is the better shape when there is such a proxy —
# the edge never sees plaintext. There isn't one here: Plex serves its own
# *.plex.direct cert, which is not valid for the name clients dial, so a
# passthrough would present a name mismatch to every client. So this terminates
# and speaks plain HTTP to Plex across the WireGuard link.
{
  lib,
  edge,
  ...
}:
let
  # HAProxy selects among several certs by SNI, so one bind line lists them all.
  certs = lib.concatMapStringsSep " " (site: "crt /var/lib/acme/${site.domain}/full.pem") edge.sites;

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
  # The cert has to exist before haproxy starts, or the bind fails and the unit
  # dies rather than degrading. On a fresh box that is the difference between
  # "waits ~30s for DNS-01" and "crash-loops until someone restarts it".
  systemd.services.haproxy = {
    after = map (site: "acme-finished-${site.domain}.target") edge.sites;
    wants = map (site: "acme-finished-${site.domain}.target") edge.sites;
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
