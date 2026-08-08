# Convenience packages for the running nodes. Deliberately not part of the golden
# image — every megabyte in there is a megabyte pushed to Proxmox over HTTP.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    jq
    vim
  ];
}
