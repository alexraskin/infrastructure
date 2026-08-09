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
    # MagicDNS rewrites /etc/resolv.conf. On a k3s node that puts the tailnet
    # resolver in front of the one k3s hands containers — leave DNS alone.
    [ "--accept-dns=false" ]
    ++ lib.optional isRouter "--advertise-routes=${lib.concatStringsSep "," routes}";
in
lib.mkIf enabled {
  services.tailscale = {
    enable = true;

    # UDP 41641, so peers connect directly instead of relaying through DERP.
    openFirewall = true;

    # Pushed by `mise run push-tailscale-key`, same pattern as the k3s token.
    # Only read when the node is not logged in yet; re-running deploy is a no-op.
    authKeyFile = "/var/lib/tailscale-authkey";

    # "server" turns on IPv4/IPv6 forwarding and relaxes rp_filter, which a
    # subnet router needs and a plain client must not have.
    useRoutingFeatures = if isRouter then "server" else "none";

    # up flags apply at first login, set flags on every start — routes have to
    # be in both or they silently disappear after the initial `tailscale up`.
    extraUpFlags = flags;
    extraSetFlags = flags;
  };

  # Subnet routes are SNATed by default, so traffic from the Mac reaches the VIP
  # with a node's LAN address as its source and hits the existing eth0 rules.
  # This line is for talking to the nodes' own tailnet addresses (ssh, 6443).
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
