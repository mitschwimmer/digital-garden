{
  description = "Digital Garden: Talos Kubernetes on IncusOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # Keep the workstation CLI on the same release as the Talos node.
      # SHA-256 verified against the upstream GitHub v1.14.5 release asset.
      talosctlPinned = pkgs.runCommand "talosctl-1.14.5" { } ''
        install -Dm755 ${pkgs.fetchurl {
          url = "https://github.com/siderolabs/talos/releases/download/v1.14.5/talosctl-linux-amd64";
          sha256 = "ff432b68986709e6b69c563a08a2ced4232d5196b0dccd6d2e783e9d714d7d7d";
        }} "$out/bin/talosctl"
      '';
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = (with pkgs; [
          age
          git
          incus
          jq
          kubectl
          kubernetes-helm
          opentofu
          sops
          virt-viewer
        ]) ++ [ talosctlPinned ];
      };
    };
}
