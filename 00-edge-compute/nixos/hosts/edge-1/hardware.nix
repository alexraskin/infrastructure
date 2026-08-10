{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
  ];

  boot.kernelParams = [
    # OCI's serial console, which is the only way in when networking is broken.
    "console=ttyS0,115200n8"
    # Predictable eth0, matching the systemd-network unit in default.nix. The
    # same trap as the cluster's "the NIC is eth0, not ens18": get it wrong and
    # the box comes up with no route and no SSH.
    "net.ifnames=0"
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
}
