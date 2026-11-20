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

  # Exit-node traffic gets the internet, not IMDS or the VCN.
  networking.firewall.extraForwardRules = ''
    iifname "tailscale0" oifname "eth0" ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10 } drop
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
