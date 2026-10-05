{
  description = "Digital Garden IncusOS homelab";

  # NixOS 26.05; upgrades are explicit changes to this immutable revision.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/0d9e9b832d03ac387417e16ce1febf73b2e631e1";

  inputs.sops-nix = {
    url = "github:Mic92/sops-nix/dcd241ba97088c22569d1573286e1b9daad340c0";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      bootstrap = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
          ./nix/hosts/edge-bootstrap.nix
        ];
      };
      edge = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
          sops-nix.nixosModules.sops
          ./nix/hosts/edge.nix
        ];
      };
      webui = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
          sops-nix.nixosModules.sops
          { nixpkgs.config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "open-webui"; }
          ./nix/hosts/open-webui.nix
        ];
      };
    in {
      nixosConfigurations.edge = edge;
      nixosConfigurations.open-webui = webui;
      packages.${system}.edge-image = pkgs.runCommand "digital-garden-edge-image" { } ''
        mkdir -p "$out"
        cp ${bootstrap.config.system.build.metadata}/tarball/*.tar.xz "$out/metadata.tar.xz"
        cp ${bootstrap.config.system.build.tarball}/tarball/*.tar.xz "$out/rootfs.tar.xz"
      '';
      packages.${system}.llama-config = pkgs.runCommand "digital-garden-llama-config" { } ''
        mkdir -p "$out"
        cp ${./llama/models.ini} "$out/models.ini"
        cp ${./llama/start.sh} "$out/start.sh"
        chmod 0444 "$out/models.ini" "$out/start.sh"
        ${pkgs.bash}/bin/bash -n "$out/start.sh"
      '';
      checks.${system} = {
        webui-roles = pkgs.runCommand "check-webui-oidc-roles" { } ''
          ${pkgs.python3}/bin/python3 ${./tests/test_webui_roles.py} ${./nix/patches/open-webui-oidc.py} ${webui.config.services.open-webui.package.src}
          touch "$out"
        '';
        authelia-config = edge.config.system.build.autheliaConfigCheck;
        caddy-config = pkgs.runCommand "check-edge-caddy-config" { } ''
        export HOME="$TMPDIR"
        export XDG_DATA_HOME="$TMPDIR/data"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        ${pkgs.caddy}/bin/caddy validate --config ${edge.config.services.caddy.configFile} --adapter caddyfile
        touch "$out"
      '';
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.opentofu pkgs.incus (pkgs.python3.withPackages (p: [ p.argon2-cffi p.pyyaml ])) pkgs.fish pkgs.age pkgs.sops pkgs.openssl pkgs.jq ];
      };
    };
}
