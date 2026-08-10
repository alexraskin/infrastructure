{
  description = "Public edge node: HAProxy on Oracle Cloud, reaching home over Tailscale";

  # Deliberately a separate flake from the repo root, not another entry in
  # hosts.json. The cluster flake is x86_64 and every node in it is a k3s node
  # built from one golden image; this is a single aarch64 box in someone else's
  # datacentre with a public IP. Sharing the flake would make the cluster's
  # `nix eval` checks depend on an Oracle instance, and vice versa.
  #
  # The flake root is this directory rather than nixos/, because edge.json sits
  # here and is shared with Terraform. A flake's source is copied into the
  # store, so `../edge.json` from a flake in nixos/ resolves to
  # /nix/store/edge.json and fails as "access to absolute path ... is forbidden
  # in pure evaluation mode". The .tf files coming along into the store is the
  # (harmless, kilobyte-sized) price.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Same reasoning as the root flake: 25.05 pins tailscale 1.82.5, which the
    # admin console flags as vulnerable. Only the package comes from here.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Declarative partitioning, applied by nixos-anywhere during install. This
    # is what makes rebuilding the box reproducible instead of a sequence of
    # steps someone remembers.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      disko,
      ...
    }:
    let
      system = "aarch64-linux";

      lib = nixpkgs.lib;

      edgeFile = builtins.fromJSON (builtins.readFile ./edge.json);

      wildcards = edgeFile.wildcards or [ ];

      certFor =
        domain:
        let
          parent = lib.concatStringsSep "." (lib.tail (lib.splitString "." domain));
        in
        if lib.elem parent wildcards then parent else domain;

      # Derived once here so acme.nix and haproxy.nix cannot disagree.
      edge = edgeFile // {
        inherit wildcards;
        certNames = lib.unique (wildcards ++ map (site: certFor site.domain) edgeFile.sites);
      };
    in
    {
      nixosConfigurations.${edge.instance.hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit edge;
          unstable = nixpkgs-unstable.legacyPackages.${system};
        };
        modules = [
          disko.nixosModules.disko
          ./nixos/hosts/edge-1
        ];
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
