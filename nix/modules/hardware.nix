# The disk layout the golden image was built with.
#
# nixos-generators' qcow format supplies these to the image, but the per-node
# configurations do not include that format module — without this they fail to
# evaluate with "The 'fileSystems' option does not specify your root file system".
{ modulesPath, cluster, ... }:
{
  # virtio_pci / virtio_scsi / sd_mod in the initrd.
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    autoResize = true;
    fsType = "ext4";
  };

  boot.growPartition = true;

  boot.loader.grub = {
    enable = true;
    # The VMs attach their disk as scsi0 on a virtio-scsi controller, so it shows
    # up as /dev/sda — not the /dev/vda the qcow format assumes. Getting this
    # wrong only bites when the bootloader is reinstalled during a switch.
    device = cluster.disk_device;
    efiSupport = false;
  };
}
