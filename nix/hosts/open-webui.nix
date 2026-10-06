{ lib, pkgs, ... }:
{
  imports = [ ./edge-bootstrap.nix ];
  networking.hostName = lib.mkForce "open-webui";
  assertions = [ {
    assertion = builtins.pathExists ../../secrets/open-webui.yaml;
    message = "Prepare encrypted WebUI inputs before building this consumer.";
  } ];
  sops = lib.mkIf (builtins.pathExists ../../secrets/open-webui.yaml) {
    defaultSopsFile = ../../secrets/open-webui.yaml;
    age.keyFile = "/var/lib/garden-secrets/age.key";
    age.sshKeyPaths = [ ];
    gnupg.sshKeyPaths = [ ];
    secrets.environment = {
      mode = "0400";
      restartUnits = [ "open-webui.service" ];
    };
  };
  services.open-webui = {
    enable = true;
    # Keep group authorization effective for the first/sole user; suppress callback logs.
    package = pkgs.open-webui.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/open-webui-oidc.patch ];
    });
    host = "0.0.0.0";
    port = 8080;
    openFirewall = false;
    environmentFile = "/run/secrets/environment";
    environment = {
      WEBUI_URL = "https://ai.archaic.work";
      WEBUI_AUTH = "true";
      WEBUI_SESSION_COOKIE_SECURE = "true";
      WEBUI_AUTH_COOKIE_SECURE = "true";
      ENABLE_LOGIN_FORM = "false";
      ENABLE_PASSWORD_AUTH = "false";
      ENABLE_SIGNUP = "false";
      ENABLE_OAUTH_SIGNUP = "true";
      ENABLE_OAUTH = "true";
      OAUTH_CLIENT_ID = "open-webui";
      OAUTH_PROVIDER_NAME = "Authelia";
      OPENID_PROVIDER_URL = "https://auth.archaic.work/.well-known/openid-configuration";
      OPENID_REDIRECT_URI = "https://ai.archaic.work/oauth/oidc/callback";
      OAUTH_SCOPES = "openid profile email groups";
      OAUTH_CODE_CHALLENGE_METHOD = "S256";
      OAUTH_TOKEN_ENDPOINT_AUTH_METHOD = "client_secret_basic";
      ENABLE_OAUTH_ROLE_MANAGEMENT = "true";
      OAUTH_ROLES_CLAIM = "groups";
      OAUTH_ALLOWED_ROLES = "ai-users,admins";
      OAUTH_ADMIN_ROLES = "admins";
      DEFAULT_USER_ROLE = "pending";
      OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "false";
      ENABLE_PERSISTENT_CONFIG = "false";
      ENABLE_OLLAMA_API = "false";
      ENABLE_OPENAI_API = "true";
      OPENAI_API_BASE_URL = "http://garden-llama.garden.internal:8080/v1";
      # Private trusted backend: this is a compatibility placeholder, not a credential.
      OPENAI_API_KEY = "unused";
      OPENAI_API_CONFIGS = builtins.toJSON { "0" = { provider = "llama.cpp"; }; };
      # Allow the first chat to wait for a cold model download/load.
      AIOHTTP_CLIENT_TIMEOUT = "7200";
      AIOHTTP_CLIENT_STREAM_IDLE_TIMEOUT = "7200";
      CORS_ALLOW_ORIGIN = "https://ai.archaic.work";
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      HF_HUB_OFFLINE = "1";
      RAG_EMBEDDING_MODEL_AUTO_UPDATE = "false";
      WHISPER_MODEL_AUTO_UPDATE = "false";
    };
  };
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ 8080 ];
  # A stable system user keeps mounted data ownership predictable across rebuilds.
  users.groups.open-webui.gid = 990;
  users.users.open-webui = { isSystemUser = true; uid = 990; group = "open-webui"; };
  systemd.services.open-webui = {
    unitConfig.RequiresMountsFor = [ "/var/lib/open-webui" "/var/lib/garden-secrets" ];
    unitConfig.ConditionPathIsMountPoint = "/var/lib/open-webui";
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "open-webui";
      Group = "open-webui";
      PrivateUsers = lib.mkForce false;
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
