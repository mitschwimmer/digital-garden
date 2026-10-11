{ open-webui, fetchFromGitHub, python3Packages }:
let
  # Backport Nixpkgs PR 572794 without changing the shared platform pin.
  version = "0.12.0";
  src = fetchFromGitHub {
    owner = "open-webui";
    repo = "open-webui";
    tag = "v${version}";
    hash = "sha256-x8Mxy7KHGqC1qmOp6/UsO7ntq07l1jrKTaR9XiOK2d0=";
  };
  frontend = open-webui.frontend.override {
    inherit version src;
    npmDepsHash = "sha256-FD433gQae9Ip5awPau83UqCezbsnyUbOgpnSka+nFng=";
  };
in
assert open-webui.version == "0.11.4";
open-webui.overrideAttrs (old: {
  inherit version src;
  dependencies = old.dependencies ++ [ python3Packages.pyotp python3Packages.qrcode ];
  makeWrapperArgs = [ "--set FRONTEND_BUILD_DIR ${frontend}/share/open-webui" ];
  passthru = (old.passthru or { }) // { inherit frontend; };
})
