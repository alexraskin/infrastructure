{
  lib,
  cluster,
  node,
  name,
  ...
}:
{
  networking.hostName = name;
  networking.domain = cluster.domain;

  # networking.hostName only lands in /etc/hostname, which systemd reads at boot.
  # Switching from the golden image would otherwise leave the live hostname as
  # "nixos" until a reboot — long enough for k3s to register under it.
  system.activationScripts.liveHostname.text = ''
    echo ${name} > /proc/sys/kernel/hostname
  '';

  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network.enable = true;

  # Static addressing baked in — identical to the cloud-init values Terraform
  # sets, so the switchover on first `nixos-rebuild` is a no-op on the wire.
  systemd.network.networks."10-lan" = {
    # Proxmox virtio NICs come up as eth0 here, but the predictable-naming policy
    # can hand out ens*/enp* on a different machine. Match every plausible name —
    # getting this wrong strands the node with no route and no SSH.
    matchConfig.Name = "en* eth*";
    address = [ "${node.ip}/${toString cluster.prefix}" ];
    routes = [ { Gateway = cluster.gateway; } ];
    networkConfig.DNS = cluster.nameservers;
    linkConfig.RequiredForOnline = "routable";
  };

  # cloud-init did its job at first boot; the config is authoritative from here.
  services.cloud-init.enable = lib.mkDefault false;

  networking.hosts."${cluster.vip}" = [ "${cluster.name}.${cluster.domain}" ];
}
