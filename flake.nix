{
  description = "Digital Garden IncusOS homelab";

  # NixOS 26.05; upgrades are explicit changes to this immutable revision.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/0d9e9b832d03ac387417e16ce1febf73b2e631e1";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      edge = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
          ./nix/hosts/edge.nix
        ];
      };
    in {
      nixosConfigurations.edge = edge;
      packages.${system}.edge-image = pkgs.runCommand "digital-garden-edge-image" { } ''
        mkdir -p "$out"
        cp ${edge.config.system.build.metadata}/tarball/*.tar.xz "$out/metadata.tar.xz"
        cp ${edge.config.system.build.tarball}/tarball/*.tar.xz "$out/rootfs.tar.xz"
      '';
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.opentofu pkgs.incus pkgs.python3 ];
      };
    };
}
