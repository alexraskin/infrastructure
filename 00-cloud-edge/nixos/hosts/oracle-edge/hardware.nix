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
    "console=ttyS0,115200n8"
    "net.ifnames=0"
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
}
