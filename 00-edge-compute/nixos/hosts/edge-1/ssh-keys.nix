# Must match TF_VAR_ssh_public_key in secrets/oci.env. cloud-init installs that
# one for root on the Ubuntu image so nixos-anywhere can get in; this is what
# NixOS installs afterwards. If they differ, the install succeeds and the switch
# locks you out of a box you can still watch running in the console.
{
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL9eDKXtB1s6U9XCukV9AdQzAsSxCdX3BpALWsaMOhm+ alex@morpheus"
  ];
}
