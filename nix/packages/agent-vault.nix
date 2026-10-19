{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation rec {
  pname = "agent-vault";
  version = "0.40.0";
  src = fetchurl {
    url = "https://github.com/Infisical/agent-vault/releases/download/v${version}/agent-vault_${version}_linux_amd64.tar.gz";
    sha256 = "aa78afc82be019c89ca186a7c6140a5e8a2bb26874b747f284e90afaf37860a0";
  };
  sourceRoot = ".";
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 agent-vault "$out/bin/agent-vault"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    AGENT_VAULT_TELEMETRY=false "$out/bin/agent-vault" version | grep -F '${version}'
  '';
  meta = {
    description = "Standalone Infisical credential broker and proxy";
    homepage = "https://github.com/Infisical/agent-vault";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "agent-vault";
  };
}
