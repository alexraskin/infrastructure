# Tailscale, as a plain client. This is how the edge reaches home at all — the
# box has no other route in, and nothing at home is port-forwarded.
#
# Different from nix/modules/tailscale.nix at the repo root in the way that
# matters: that one makes the k3s servers subnet *routers* advertising
# 10.0.200.0/24. This one is a leaf.
{ unstable, ... }:
let
  # No --accept-routes. The Plex host is its own tailnet device, so the backend
  # in edge.json is a peer address and the cluster's advertised 10.0.200.0/24 is
  # not needed to reach it.
  #
  # Leaving it off is the point, not an oversight: this is the one machine here
  # with a public IP, and accepting the subnet route would give it a path to
  # every host on the home LAN rather than to the one service it proxies. It
  # also removes the hairpin through whichever k3s server currently owns the
  # route — the edge holds a direct WireGuard path to the Plex host instead.
  #
  # Both lists, or the flags are dropped after the first `tailscale up` — the
  # same trap as the cluster module.
  flags = [ "--accept-dns=false" ];
in
{
  services.tailscale = {
    enable = true;

    # 25.05 ships 1.82.5, which the admin console flags as vulnerable. Only the
    # package comes from unstable; everything else on this box stays on 25.05.
    package = unstable.tailscale;

    # UDP 41641, so the Plex host can reach this box directly rather than
    # relaying through DERP. On a link carrying video that is not a detail.
    openFirewall = true;

    authKeyFile = "/var/lib/tailscale-authkey";

    # No routes advertised and no exit-node duty, so no IP forwarding.
    useRoutingFeatures = "none";

    extraUpFlags = flags;
    extraSetFlags = flags;
  };

  # The pre-auth key must be a *tagged* one, for the same reason as the cluster:
  # user-owned keys expire ~180 days after enrolment and take the device with
  # them. The tag is also what the ACL matches to allow this box the Plex host's
  # 32400 and nothing else. Tags come from the key or the admin console, never
  # from this module: `tailscale set` has no --advertise-tags.
}
