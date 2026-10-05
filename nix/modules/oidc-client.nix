{
  client_id = "open-webui";
  client_name = "Open WebUI";
  public = false;
  authorization_policy = "two_factor";
  require_pkce = true;
  pkce_challenge_method = "S256";
  redirect_uris = [ "https://ai.archaic.work/oauth/oidc/callback" ];
  scopes = [ "openid" "profile" "email" "groups" ];
  response_types = [ "code" ];
  grant_types = [ "authorization_code" ];
  access_token_signed_response_alg = "none";
  userinfo_signed_response_alg = "none";
  token_endpoint_auth_method = "client_secret_basic";
}
