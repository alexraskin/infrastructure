{ pkgs, unstable, ... }:
let

  flags = [
    "--accept-dns=true"
    "--ssh"
    "--advertise-tags=tag:edge"
    "--advertise-exit-node"
  ];
in
{
  services.tailscale = {
    enable = true;

    package = unstable.tailscale;

    openFirewall = true;

    authKeyFile = "/var/lib/tailscale-authkey";

    useRoutingFeatures = "server";

    extraUpFlags = flags;
    extraSetFlags = flags;
  };

  # The nftables forward chain is policy drop and knows nothing about
  # trustedInterfaces, so without this every exit-node packet is dropped.
  networking.firewall.extraForwardRules = ''
    iifname "tailscale0" accept
  '';

  # Tailscale's UDP throughput tuning for routers. Not persistent by itself.
  systemd.services.tailscale-offloads = {
    description = "UDP GRO forwarding on the uplink, for exit-node throughput";
    after = [ "sys-subsystem-net-devices-eth0.device" ];
    bindsTo = [ "sys-subsystem-net-devices-eth0.device" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -K eth0 rx-udp-gro-forwarding on rx-gro-list off";
    };
  };
}
