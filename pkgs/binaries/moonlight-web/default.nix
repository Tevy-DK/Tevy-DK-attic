{
  lib,
  stdenv,
  fetchurl,
}:

# Upstream ships a cross-built musl release for both Linux architectures.  The
# tarball contains a `package/` directory with the `web-server` executable and
# the prebuilt web UI under `static/`.
let
  isAarch64 = stdenv.hostPlatform.isAarch64;
  target = if isAarch64 then "aarch64-unknown-linux-musl" else "x86_64-unknown-linux-musl";
  hash =
    if isAarch64 then
      "sha256-L5gYYsIiza7MSExpnwa66Ser7hZwhTWr60hlO+hV++w="
    else
      "sha256-HVYjlXnwWFKvfArB7LHpXBpsEjeZ9O2rn+bRVTZKaH4=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "moonlight-web";
  version = "3.0.1";

  src = fetchurl {
    url = "https://github.com/MrCreativ3001/moonlight-web-stream/releases/download/v${finalAttrs.version}/moonlight-web-${target}.tar.gz";
    inherit hash;
  };

  sourceRoot = "package";
  dontConfigure = true;
  dontBuild = true;
  # The upstream musl binary is static-pie (x86_64) / static (aarch64) and
  # ships unstripped; keep stdenv's default strip, but do not patch the ELF.
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/moonlight-web" "$out/bin"
    cp -r static "$out/lib/moonlight-web/static"
    install -Dm755 web-server "$out/lib/moonlight-web/web-server"
    install -Dm755 ${./wrapper.sh} "$out/bin/moonlight-web"
    substituteInPlace "$out/bin/moonlight-web" \
      --subst-var out \
      --subst-var-by shell ${stdenv.shell}

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR $out/bin/moonlight-web --version | grep -qx "web-server ${finalAttrs.version}"
    HOME=$TMPDIR $out/bin/moonlight-web config print | grep -q '"bind_address"'
    runHook postInstallCheck
  '';

  meta = {
    description = "Unofficial Moonlight client that streams Sunshine hosts to a web browser";
    homepage = "https://github.com/MrCreativ3001/moonlight-web-stream";
    changelog = "https://github.com/MrCreativ3001/moonlight-web-stream/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "moonlight-web";
  };
})
