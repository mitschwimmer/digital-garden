{
  config,
  lib,
  pkgs,
  ...
}:
let
  network = builtins.fromJSON (builtins.readFile ../../agent-network.json);
  pi = pkgs.callPackage ../../nix/packages/pi.nix { };
  caReady = builtins.pathExists ../agent-vault/ca.pem;
  launcher =
    pkgs.runCommand "garden-agent"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p "$out/bin"
        makeWrapper ${pkgs.python3}/bin/python "$out/bin/garden-agent" \
          --add-flags ${../../operations/agent_session.py} \
          --add-flags /etc/garden-agent/session.json \
          --add-flags ${pi}/bin/pi
      '';
in
{
  users.groups.pi.gid = 1000;
  users.users.pi = {
    isNormalUser = true;
    uid = 1000;
    group = "pi";
    home = "/home/pi";
    createHome = false;
    shell = pkgs.fish;
  };
  programs.fish.enable = true;
  security.sudo.enable = false;

  # Bootstrap the vault first, retrieve its public CA through authenticated
  # Incus exec, review it, then commit ca.pem and rebuild this guest.
  security.pki.certificateFiles = lib.optional caReady ../agent-vault/ca.pem;
  environment.etc = {
    "garden-agent/session.json".text = builtins.toJSON {
      inherit caReady;
      proxyHost = network.vaultIPv4;
      proxyPort = network.proxyPort;
      vault = "pi-agent";
      tokenFile = "/run/garden-agent/token";
      caBundle = config.security.pki.caBundle;
    };
    "garden-agent/models.json".source = ./models.json;
    "garden-agent/settings.json".source = ./settings.json;
  };
  # The daemon starts through the same runtime credential reader as Pi.
  # Stage a proxy-only token, then restart the daemon when rotating sessions.
  nix.settings = {
    sandbox = true;
    sandbox-fallback = false;
    ssl-cert-file = config.security.pki.caBundle;
    extra-sandbox-paths = [ config.security.pki.caBundle ];
  };
  systemd.services.nix-daemon = {
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig.ExecStart = [
      ""
      "${launcher}/bin/garden-agent --allow-missing-session -- ${config.nix.package.out}/bin/nix-daemon --daemon"
    ];
  };

  environment.systemPackages = with pkgs; [
    pi
    launcher
    git
    gh
    go
    nodejs_22
    gcc
    gnumake
    pkg-config
    python3
    ripgrep
    fd
    jq
    tmux
    ghostty.terminfo
    cacert
  ];
  systemd.tmpfiles.rules = [
    "d /home/pi 0700 pi pi -"
    "d /home/pi/workspace 0700 pi pi -"
    "d /home/pi/.pi 0700 pi pi -"
    "d /home/pi/.pi/agent 0700 pi pi -"
    "L+ /home/pi/.pi/agent/models.json - - - - /etc/garden-agent/models.json"
    "L+ /home/pi/.pi/agent/settings.json - - - - /etc/garden-agent/settings.json"
    # Operator stages an expiring proxy token here; no admin token is installed.
    "d /run/garden-agent 0750 root pi -"
  ];
}
