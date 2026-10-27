{
  config,
  pkgs,
  unstable,
  ...
}:
let

  flags = [
    "--accept-dns=true"
    "--ssh"
    "--advertise-exit-node"
  ];
in
{
  services.tailscale = {
    enable = true;

    package = unstable.tailscale;

    openFirewall = true;

    authKeyFile = config.sops.secrets.tailscale_authkey.path;

    useRoutingFeatures = "server";

    extraUpFlags = flags;
    extraSetFlags = flags;
  };

  # Refuses SSH -L/-R (TCP and unix socket) and agent forwarding, whatever the policy grants.
  systemd.services.tailscaled.environment.TS_SSH_DISABLE_FORWARDING = "1";

  networking.firewall.extraForwardRules = ''
    iifname "tailscale0" accept
  '';

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
