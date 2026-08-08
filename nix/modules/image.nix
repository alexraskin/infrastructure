# Only used for the golden qcow2 image. Deployed hosts get network.nix instead.
{ ... }:
{
  # Proxmox hands the VM a cloud-init drive (ConfigDrive/NoCloud) carrying the
  # hostname, IP and SSH key that Terraform put in `initialization {}`.
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings.datasource_list = [
      "NoCloud"
      "ConfigDrive"
      "None"
    ];
  };

  systemd.network.enable = true;
  networking.useNetworkd = true;
  networking.useDHCP = false;

  # Grow the root partition to whatever disk size Terraform asked for.
  boot.growPartition = true;
}
