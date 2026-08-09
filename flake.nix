{
  description = "HA k3s cluster on NixOS running on Proxmox VE";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Only for tailscale. 25.05 pins 1.82.5, which the admin console flags as
    # vulnerable; tailscale expects clients to track its own release train, not a
    # distro's stable branch. Everything else stays on 25.05 — see nix/modules/tailscale.nix.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-generators,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      hosts = builtins.fromJSON (builtins.readFile ./hosts.json);
      cluster = hosts.cluster;
      nodes = hosts.nodes;

      # The server that runs `--cluster-init`; every other server joins it.
      bootstrapIp = nodes.${cluster.bootstrap}.ip;

      roleModule = role: if role == "server" then ./nix/modules/k3s-server.nix else ./nix/modules/k3s-agent.nix;

      mkNode =
        name: node:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              cluster
              node
              name
              bootstrapIp
              ;
            unstable = nixpkgs-unstable.legacyPackages.${system};
          };
          modules = [
            ./nix/modules/base.nix
            ./nix/modules/hardware.nix
            ./nix/modules/network.nix
            ./nix/modules/tailscale.nix
            ./nix/modules/monitoring.nix
            ./nix/modules/tools.nix
            (roleModule node.role)
          ];
        };
    in
    {
      nixosConfigurations = lib.mapAttrs mkNode nodes;

      # Generic golden image: no node identity, gets IP/hostname from Proxmox cloud-init
      # on first boot, then `nixos-rebuild --target-host` replaces it with the real config.
      packages.${system} = rec {
        image = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow";
          modules = [
            ./nix/modules/base.nix
            ./nix/modules/image.nix
          ];
        };
        default = image;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          terraform
          kubectl
          kubernetes-helm
          jq
        ];
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
