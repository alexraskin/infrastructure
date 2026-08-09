# Tailscale, so the cluster is reachable from outside the LAN.
#
# The servers advertise the whole cluster subnet rather than the tailnet talking
# to individual nodes: a remote kubectl then keeps using the kube-vip VIP and
# stays HA. Tailscale fails a route over to another advertiser on its own, so
# three route-advertising servers means losing one is a no-op.
#
# Deliberately not part of base.nix — the golden image would carry the tailscale
# closure to Proxmox for nothing, and image nodes have no identity to log in with.
{
  lib,
  cluster,
  node,
  ...
}:
let
  ts = cluster.tailscale or { };
  enabled = ts.enable or false;
  routes = ts.advertise_routes or [ ];
  isRouter = node.role == "server" && routes != [ ];

  flags =
    [ "--accept-dns=false" ]
    ++ lib.optional isRouter "--advertise-routes=${lib.concatStringsSep "," routes}";
in
lib.mkIf enabled {
  services.tailscale = {
    enable = true;

    # UDP 41641, so peers connect directly instead of relaying through DERP.
    openFirewall = true;

    authKeyFile = "/var/lib/tailscale-authkey";

    useRoutingFeatures = if isRouter then "server" else "none";

    extraUpFlags = flags;
    extraSetFlags = flags;
  };

  # Subnet routes are SNATed by default, so traffic from the Mac reaches the VIP
  # with a node's LAN address as its source and hits the existing eth0 rules.
  # This line is for talking to the nodes' own tailnet addresses (ssh, 6443).
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
