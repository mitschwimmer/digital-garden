{ config, lib, pkgs, ... }:
let
  encrypted = ../../secrets/edge.yaml;
  ready = builtins.pathExists encrypted;
  runtime = name: "/run/secrets/authelia-" + name;
  settings = {
    theme = "auto";
    default_2fa_method = "totp";
    server.address = "tcp://127.0.0.1:9091/";
    log.level = "info";
    authentication_backend = {
      password_reset.disable = true;
      file = { path = runtime "users"; watch = false; };
    };
    access_control.default_policy = "deny";
    session = {
      name = "garden_session";
      same_site = "lax";
      expiration = "1h";
      inactivity = "5m";
      cookies = [ {
        domain = "archaic.work";
        authelia_url = "https://auth.archaic.work";
      } ];
    };
    storage.local.path = "/var/lib/authelia-main/db.sqlite3";
    totp.issuer = "Digital Garden";
    regulation = { max_retries = 5; find_time = "2m"; ban_time = "5m"; };
  };
in {
  # CI can build without operator ciphertext; deployment requires it explicitly.
  sops = lib.mkIf ready {
    defaultSopsFile = encrypted;
    age.keyFile = "/var/lib/garden-secrets/age.key";
    age.sshKeyPaths = [ ];
    gnupg.sshKeyPaths = [ ];
    secrets = builtins.listToAttrs (map (name: {
      name = "authelia-" + name;
      value = {
        key = name;
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
        restartUnits = [ "authelia-main.service" ];
      };
    }) [ "jwt" "session" "storage" "users" "smtp" ]);
  };

  services.authelia.instances.main = {
    enable = true;
    inherit settings;
    settingsFiles = [ (runtime "smtp") ];
    secrets = {
      jwtSecretFile = runtime "jwt";
      sessionSecretFile = runtime "session";
      storageEncryptionKeyFile = runtime "storage";
    };
  };
  systemd.services.authelia-main = {
    unitConfig.ConditionPathIsMountPoint = "/var/lib/authelia-main";
    requiresMountsFor = [ "/var/lib/authelia-main" "/var/lib/garden-secrets" ];
    # Incus already supplies user isolation; nested user namespaces are unnecessary.
    serviceConfig.PrivateUsers = lib.mkForce false;
  };
  services.caddy.virtualHosts."auth.archaic.work" = {
    logFormat = "output stderr";
    extraConfig = "reverse_proxy 127.0.0.1:9091";
  };

  # Validate real settings with clearly synthetic secrets, without contacting SMTP.
  system.build.autheliaConfigCheck = let
    yaml = pkgs.formats.yaml { };
    testConfig = yaml.generate "authelia-test.yaml" (lib.recursiveUpdate settings {
      authentication_backend.file.path = "/tmp/garden-test-users.json";
      identity_validation.reset_password.jwt_secret = "CI-only-jwt-secret-not-used-in-deployments";
      session.secret = "CI-only-session-secret-not-used-in-deployments";
      storage.encryption_key = "CI-only-storage-key-not-used-in-deployments";
      notifier.smtp = {
        address = "submission://smtp.example.invalid:587";
        username = "ci";
        password = "CI-only-smtp-password";
        sender = "Authelia <ci@example.invalid>";
      };
    });
  in pkgs.runCommand "check-authelia-config" { } ''
    ${pkgs.authelia}/bin/authelia validate-config --config ${testConfig}
    touch "$out"
  '';
}
