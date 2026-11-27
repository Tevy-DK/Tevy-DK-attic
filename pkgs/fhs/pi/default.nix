{
  lib,
  stdenv,
  buildFHSEnv,
  fetchurl,
  makeWrapper,
}:

# pi ships a Bun single-file executable plus its runtime assets in the release
# tarball.  Run it inside an FHS root because extensions commonly hard-code
# absolute paths such as /usr/bin/python3 or /bin/bash, and the executable's
# ELF interpreter is the standard /lib64 path.  The tool list is deliberately
# broad: it is the runtime surface for plugins we do not control, not a
# dependency list derived from pi itself.  Plugins are installed by pi at
# runtime; nothing here configures or declares them.
let
  version = "1.7.0";
  isAarch64 = stdenv.hostPlatform.isAarch64;
  assetSuffix = if isAarch64 then "arm64" else "x64";
  hash =
    if isAarch64 then
      "sha256-zSCc/JD7lPtLAMzXhajWSkoVT5JOUviP6+ts821cmiQ="
    else
      "sha256-QvftZ+g/cn/lHdJ0bVDcRcfReEFZqVGClqKCQCrGj0o=";

  pi-unwrapped = stdenv.mkDerivation {
    pname = "pi-unwrapped";
    inherit version;

    src = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-${assetSuffix}.tar.gz";
      inherit hash;
    };

    sourceRoot = "pi";

    dontConfigure = true;
    dontBuild = true;
    # The Bun executable carries an appended payload; stripping rewrites the
    # ELF and destroys it.
    dontStrip = true;

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/pi" "$out/bin"
      cp -a . "$out/lib/pi"

      # The Bun binary resolves bundled assets relative to process.execPath.
      # Pin the package directory so the wrapper works even when the binary is
      # reached through the FHS /usr/bin symlink.
      makeWrapper "$out/lib/pi/pi" "$out/bin/pi" \
        --set-default PI_PACKAGE_DIR "$out/lib/pi"

      runHook postInstall
    '';
  };

  tools =
    pkgs: with pkgs; [
      # The release binary and the Node.js runtime its extensions may spawn.
      pi-unwrapped
      nodejs

      # Language runtimes plugins invoke directly.
      bun
      deno
      python3
      uv
      go
      rustc
      cargo

      # Version control, network and transfer.
      git
      git-lfs
      gh
      openssh
      rsync
      curl
      wget
      aria2
      gnupg

      # Search, text processing and data inspection.
      ripgrep
      fd
      fzf
      bat
      eza
      tree
      jq
      yq-go
      sd
      sqlite
      file
      which
      procps
      psmisc
      util-linux
      shellcheck
      shfmt

      # Archives plugins unpack or produce.
      unzip
      zip
      p7zip
      zstd

      # Native toolchain for extensions that build addons.
      gnumake
      cmake
      gcc
      pkg-config
      autoconf
      automake
      libtool

      # TypeScript/JavaScript tooling hard-coded by some plugins.
      typescript
      tsx
      prettier

      # Media helpers and the X11 library used by pi's native platform addon.
      imagemagick
      ffmpeg
      libxcb
    ];
in
buildFHSEnv {
  pname = "pi";
  inherit version;

  # buildFHSEnv already provides bash, coreutils, findutils, sed, grep, awk,
  # diffutils, tar, gzip, bzip2, xz and less at their standard paths.
  targetPkgs = tools;

  runScript = "pi";

  meta = {
    description = "pi coding agent release binary in an FHS environment with common plugin tools";
    homepage = "https://pi.dev/";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "pi";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
