{
  description = "Digital Garden isolated IncusOS systems";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/26f4107e47e3ad0ffd0db220469ba83b6f6d96e8";
  # Immich 2 at the shared stable pin is unsupported; isolate its supported pin.
  inputs.nixpkgs-immich.url = "github:NixOS/nixpkgs/55bfb4d7437bd4e09ab7cba58a43bd68eb310044";
  inputs.sops-nix = {
    url = "github:Mic92/sops-nix/44931708c62937c2b1bf7953902989fa5bb9ee1b";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-immich,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs { inherit system; };
      names = [
        "edge"
        "identity"
        "immich"
        "webdav"
        "agent-vault"
        "pi"
      ];
      mkSystem =
        name: seed:
        let
          guestNixpkgs = if name == "immich" then nixpkgs-immich else nixpkgs;
        in
        guestNixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${guestNixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
            ./nix/modules/container.nix
            {
              networking.hostName = name;
              environment.etc."garden-system".text = name + "\n";
            }
          ]
          ++
            lib.optionals
              (builtins.elem name [
                "agent-vault"
                "pi"
              ])
              [
                (./systems + "/${name}/network.nix")
              ]
          ++ lib.optionals (!seed) [
            sops-nix.nixosModules.sops
            (./systems + "/${name}/configuration.nix")
          ];
        };
      guests = lib.genAttrs names (name: mkSystem name false);
      seeds = lib.genAttrs names (name: mkSystem name true);
      webdavRoute =
        cidrs:
        (guests.edge.extendModules {
          modules = [ { garden.webdavLanCidrs = lib.mkForce cidrs; } ];
        }).config.services.caddy.virtualHosts."webdav.archaic.work".extraConfig;
    in
    {
      nixosConfigurations = guests;
      packages.${system} = lib.genAttrs (map (name: "${name}-image") names) (
        image:
        let
          name = lib.removeSuffix "-image" image;
          seed = seeds.${name};
        in
        pkgs.runCommand "digital-garden-${name}-image" { } ''
          mkdir -p "$out"
          cp ${seed.config.system.build.metadata}/tarball/*.tar.xz "$out/metadata.tar.xz"
          cp ${seed.config.system.build.tarball}/tarball/*.tar.xz "$out/rootfs.tar.xz"
          printf '%s\n' '${name}' > "$out/garden-system"
        ''
      );
      checks.${system} = {
        caddy-config = pkgs.runCommand "check-caddy-config" { } ''
          export HOME="$TMPDIR"
          export XDG_DATA_HOME="$TMPDIR/data"
          export XDG_CONFIG_HOME="$TMPDIR/config"
          ${pkgs.caddy}/bin/caddy validate --config ${guests.edge.config.services.caddy.configFile} --adapter caddyfile
          touch "$out"
        '';
        webdav-ingress = pkgs.runCommand "check-webdav-ingress" { } ''
          ${pkgs.python3}/bin/python ${./tests/check_webdav_ingress.py} \
            ${pkgs.caddy}/bin/caddy \
            ${pkgs.writeText "webdav-deny-route" (webdavRoute [ ])} \
            ${pkgs.writeText "webdav-lan-route" (webdavRoute [ "127.0.0.2/32" ])}
          touch "$out"
        '';
        webdav-accounts = pkgs.runCommand "check-webdav-accounts" { } ''
          ${pkgs.python3}/bin/python ${./tests/check_webdav_accounts.py} \
            ${pkgs.webdav}/bin/webdav \
            ${pkgs.writeText "webdav-settings.json" (
              builtins.toJSON guests.webdav.config.services.webdav.settings
            )}
          touch "$out"
        '';
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          opentofu
          incus
          age
          sops
          openssl
          jq
          nixfmt
          python3
          gh
          kanidm_1_11
        ];
      };
    };
}
