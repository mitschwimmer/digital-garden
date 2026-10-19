{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  libxcb,
  ripgrep,
  fd,
}:
stdenv.mkDerivation rec {
  pname = "pi";
  version = "1.3.0";
  src = fetchurl {
    url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
    sha256 = "24f5be328b66d4da36876296989501974f43ab8434fbb57c35c523a3ea505ded";
  };
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    libxcb
  ];
  dontBuild = true;
  # Pi embeds its Bun runtime; retain the executable's appended payload.
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/pi" "$out/bin"
    cp -R . "$out/lib/pi"
    makeWrapper "$out/lib/pi/pi" "$out/bin/pi" \
      --prefix PATH : ${lib.makeBinPath [ ripgrep fd ]}
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    test "$("$out/bin/pi" --version)" = '${version}'
  '';
  meta = {
    description = "Pi coding agent with bundled Bun runtime";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "pi";
  };
}
