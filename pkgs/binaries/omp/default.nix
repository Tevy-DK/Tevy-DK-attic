{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

# Upstream's omp-linux-musl-* assets are NOT static: they link musl's
# libstdc++.so.6 and libgcc_s.so.1.  NixOS is a glibc distribution, and
# pointing LD_LIBRARY_PATH at a musl libstdc++ breaks glibc children spawned by
# omp (node, for example).  The glibc release asset is the same version and is
# the correct runtime for NixOS.
let
  isAarch64 = stdenv.hostPlatform.isAarch64;
  assetSuffix = if isAarch64 then "arm64" else "x64";
  hash =
    if isAarch64 then
      "sha256-H9MfHJRxo/hBdXHLqFfeD6LsFni5PVJRdQEguqs0YOY="
    else
      "sha256-AtdqDP7uRz/6OH9QzwN4sN4cRGhMg+Z8onuk1xfPsNA=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "omp";
  version = "18.14.1";

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${finalAttrs.version}/omp-linux-${assetSuffix}";
    inherit hash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # The release is a Bun single-file executable; stripping it can destroy the
  # appended payload.
  dontStrip = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  # The executable lists the ELF interpreter itself as a DT_NEEDED entry.  It
  # is supplied by autoPatchelfHook's interpreter rewrite, not as a normal
  # shared library, so do not fail the build over it.
  autoPatchelfIgnoreMissingDeps = [
    "ld-linux-x86-64.so.2"
    "ld-linux-aarch64.so.1"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/omp"
    runHook postInstall
  '';

  meta = {
    description = "Terminal coding agent from oh-my-pi, installed from the upstream release";
    homepage = "https://github.com/can1357/oh-my-pi";
    changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "omp";
  };
})
