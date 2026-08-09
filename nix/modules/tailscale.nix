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
  unstable,
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

    # 25.05 ships 1.82.5, which the admin console flags as vulnerable. Tailscale
    # expects clients to track its own release train, not a distro's stable
    # branch, so the package — and only the package — comes from the pinned
    # nixpkgs-unstable rev in flake.lock. This is the sole consumer of that
    # input; without this line the `unstable` in specialArgs does nothing and
    # the nodes silently run 25.05's version.
    package = unstable.tailscale;

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
