{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
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
      "sha256-wr4eqFzhfEJwhUtX7/8qfqHVoDx1V/0Ich8rm7MmmN4="
    else
      "sha256-ZJjteFurANKSbgOH4OwCNi1tRfHD0NG1fBYYt/lckmQ=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "omp";
  version = "18.16.0";

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

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
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

  # omp installs its local-inference runtime at first use (fastembed plus
  # prebuilt onnxruntime-node/tokenizers binaries under ~/.omp/cache).  Those
  # addons are dlopen'd, carry their own DT_RUNPATH, and need the glibc
  # libstdc++.so.6/libgcc_s.so.1 that NixOS does not put on the default search
  # path.  They never exist at build time, so autoPatchelfHook cannot patch
  # them, and the executable's own RPATH is not consulted for an addon's
  # dependencies.  omp reads OMP_NATIVE_LIBRARY_PATH and appends it to
  # LD_LIBRARY_PATH for inference worker subprocesses only, which keeps the
  # path out of the bash/eval/daemon children; --set-default leaves a user's
  # own value in charge.
  postFixup = ''
    wrapProgram "$out/bin/omp" \
      --set-default OMP_NATIVE_LIBRARY_PATH "${
        lib.makeLibraryPath (
          [ stdenv.cc.cc.lib ] ++ lib.optional (stdenv.cc.cc ? libgcc) stdenv.cc.cc.libgcc
        )
      }"
  '';

  # Prove the advertised runtime libraries actually load from that path, and
  # that workers spawned through the wrapper still start.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR $out/bin/omp --smoke-test | grep -q "smoke-test: ok"
    env -u LD_LIBRARY_PATH HOME=$TMPDIR BUN_BE_BUN=1 $out/bin/omp -e '
      const { dlopen } = require("bun:ffi");
      const dirs = (process.env.OMP_NATIVE_LIBRARY_PATH || "").split(":").filter(Boolean);
      const need = {
        "libstdc++.so.6": { __cxa_demangle: { args: ["ptr", "ptr", "ptr", "ptr"], returns: "ptr" } },
        "libgcc_s.so.1": { _Unwind_Backtrace: { args: ["ptr", "ptr"], returns: "i32" } },
      };
      for (const lib of Object.keys(need)) {
        if (!dirs.some((dir) => { try { dlopen(dir + "/" + lib, need[lib]); return true; } catch { return false; } })) {
          console.error("unresolved: " + lib);
          process.exit(1);
        }
      }
    '
    runHook postInstallCheck
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
