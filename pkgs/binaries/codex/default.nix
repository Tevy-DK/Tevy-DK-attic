{
  lib,
  stdenv,
  fetchurl,
}:

let
  target =
    if stdenv.hostPlatform.isAarch64 then "aarch64-unknown-linux-musl" else "x86_64-unknown-linux-musl";
  hash =
    if stdenv.hostPlatform.isAarch64 then
      "sha256-hDSJrLTUsQeXRcNrA8WWO4h7gxVa8gj9U1hOM+6OsoE="
    else
      "sha256-nWSDYQbVs3TpDuRFTH683nynEGVYvX5Bo0ufJuvaJRo=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.167.0";

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-${target}.tar.gz";
    inherit hash;
  };

  # The tarball contains the bare binary at its root.
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # The upstream binary is static-pie and already stripped.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "codex-${target}" "$out/bin/codex"
    runHook postInstall
  '';

  meta = {
    description = "OpenAI Codex CLI, installed from the upstream static musl release";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "codex";
  };
})
