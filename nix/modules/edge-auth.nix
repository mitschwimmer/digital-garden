{ config, lib, pkgs, ... }:
let
  encrypted = ../../secrets/edge.yaml;
  oidcEncrypted = ../../secrets/edge-oidc.yaml;
  oidcClient = import ./oidc-client.nix;
  clientConfigFor = path: pkgs.writeText "oidc-client.yaml" (builtins.replaceStrings
    [ "\"GARDEN_CLIENT_SECRET\"" ]
    [ "{{ secret \"${path}\" | msquote }}" ]
    (builtins.toJSON { identity_providers.oidc.clients = [
      (oidcClient // { client_secret = "GARDEN_CLIENT_SECRET"; })
    ]; }));
  clientConfig = clientConfigFor "/run/secrets/authelia-oidc-client";
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
    access_control = {
      default_policy = "deny";
      rules = [ { domain = "*.archaic.work"; policy = "two_factor"; } ];
    };
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
  assertions = [ {
    assertion = ready && builtins.pathExists oidcEncrypted;
    message = "Prepare encrypted Authelia and OIDC inputs before building this consumer.";
  } ];
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
    }) [ "jwt" "session" "storage" "users" "smtp" ]) //
      lib.optionalAttrs (builtins.pathExists oidcEncrypted) (builtins.listToAttrs
        (map (name: {
          name = "authelia-oidc-" + name;
          value = {
            sopsFile = oidcEncrypted;
            key = name;
            owner = "authelia-main";
            group = "authelia-main";
            mode = "0400";
            restartUnits = [ "authelia-main.service" ];
          };
        }) [ "hmac" "signing" "client" ]));
  };

  services.authelia.instances.main = {
    enable = true;
    inherit settings;
    settingsFiles = [ (runtime "smtp") clientConfig ];
    secrets = {
      oidcHmacSecretFile = runtime "oidc-hmac";
      oidcIssuerPrivateKeyFile = runtime "oidc-signing";
      jwtSecretFile = runtime "jwt";
      sessionSecretFile = runtime "session";
      storageEncryptionKeyFile = runtime "storage";
    };
  };
  systemd.services.authelia-main = {
    unitConfig.ConditionPathIsMountPoint = "/var/lib/authelia-main";
    unitConfig.RequiresMountsFor = [ "/var/lib/authelia-main" "/var/lib/garden-secrets" ];
    # Incus already supplies user isolation; nested user namespaces are unnecessary.
    serviceConfig.PrivateUsers = lib.mkForce false;
  };
  # Route this private DNS suffix to the DHCP-provided Incus resolver.
  systemd.network.networks."10-backend".networkConfig.Domains = [ "~garden.internal" ];
  services.caddy.virtualHosts."ai.archaic.work" = {
    logFormat = null;
    extraConfig = "reverse_proxy open-webui.garden.internal:8080";
  };
  services.caddy.virtualHosts."auth.archaic.work" = {
    # Verification URLs may contain tokens; keep them out of HTTP access logs.
    logFormat = null;
    extraConfig = "reverse_proxy 127.0.0.1:9091";
  };

  # Validate real settings with clearly synthetic secrets, without contacting SMTP.
  system.build.autheliaConfigCheck = let
    yaml = pkgs.formats.yaml { };
    jwksConfig = pkgs.writeText "ci-oidc-jwks.yaml" ''
      identity_providers:
        oidc:
          jwks:
            - key: {{ secret "/tmp/garden-ci-key.pem" | mindent 10 "|" | msquote }}
    '';
    testConfig = yaml.generate "authelia-test.yaml" (lib.recursiveUpdate settings {
      authentication_backend.file.path = "/tmp/garden-test-users.json";
      identity_validation.reset_password.jwt_secret = "CI-only-jwt-secret-not-used-in-deployments";
      session.secret = "CI-only-session-secret-not-used-in-deployments";
      storage.encryption_key = "CI-only-storage-key-not-used-in-deployments";
      identity_providers.oidc = {
        hmac_secret = "CI-only-oidc-hmac-secret-not-used-in-deployments";
      };
      notifier.smtp = {
        address = "submission://smtp.example.invalid:587";
        username = "ci";
        password = "CI-only-smtp-password";
        sender = "Authelia <ci@example.invalid>";
      };
    });
  in pkgs.runCommand "check-authelia-config" { } ''
    ${pkgs.openssl}/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/garden-ci-key.pem 2>/dev/null
    ${pkgs.authelia}/bin/authelia crypto hash generate argon2 --password CI-only-client-secret-not-used-in-deployments | ${pkgs.gnused}/bin/sed -n 's/^Digest: //p' > /tmp/garden-ci-client
    export X_AUTHELIA_CONFIG_FILTERS=template
    ${pkgs.authelia}/bin/authelia validate-config --config ${testConfig},${jwksConfig},${clientConfigFor "/tmp/garden-ci-client"}
    touch "$out"
  '';
}
