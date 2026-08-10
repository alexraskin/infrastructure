{
  description = "Public edge node: HAProxy on Oracle Cloud, reaching home over Tailscale";


  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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
