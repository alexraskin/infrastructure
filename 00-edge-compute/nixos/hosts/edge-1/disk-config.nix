{
  disko.devices.disk.main = {
    type = "disk";

    # A1.Flex boot volumes attach as paravirtualised SCSI, so /dev/sda. The x86
    # shapes hand out /dev/nvme0n1 instead — this is the line to change if the
    # shape in edge.json ever moves off Ampere.
    device = "/dev/sda";

    content = {
      type = "gpt";
      partitions = {
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
