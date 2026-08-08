{ lib, ... }:
{
  system.stateVersion = "25.05";

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Serial console so `qm terminal <vmid>` works from the Proxmox host.
  boot.kernelParams = [ "console=ttyS0,115200" ];
  boot.loader.timeout = lib.mkDefault 1;

  services.qemuGuest.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL9eDKXtB1s6U9XCukV9AdQzAsSxCdX3BpALWsaMOhm+ alex@morpheus"
  ];

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  time.timeZone = "UTC";
  services.timesyncd.enable = true;
  documentation.enable = false;
  documentation.nixos.enable = false;
}
