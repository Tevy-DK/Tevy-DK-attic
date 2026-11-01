{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  makeDesktopItem,
  # Runtime libraries from the Debian control file plus Electron's usual set.
  alsa-lib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libappindicator-gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libsecret,
  libX11,
  libXScrnSaver,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxcb,
  libxkbcommon,
  libXtst,
  nspr,
  nss,
  pango,
  udev,
  util-linux,
  vulkan-loader,
  xdg-utils,
}:

let
  desktopItem = makeDesktopItem {
    name = "command-code";
    desktopName = "Command Code";
    genericName = "AI coding agent";
    comment = "Command Code desktop app";
    exec = "command-code %U";
    icon = "command-code";
    terminal = false;
    categories = [ "Development" ];
    startupWMClass = "command-code";
    mimeTypes = [ "x-scheme-handler/commandcode" ];
  };

  # Electron apps dlopen these at runtime, so they are not in DT_NEEDED and
  # autoPatchelfHook cannot discover them.
  runtimeLibraries = [
    libappindicator-gtk3
    libdrm
    libGL
    libnotify
    libsecret
    libXScrnSaver
    libXtst
    udev
    util-linux
    vulkan-loader
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "command-code";
  version = "0.1.60";

  # Upstream publishes only an x86_64 .deb for Linux.
  src = fetchurl {
    url = "https://github.com/CommandCodeAI/desktop/releases/download/v${finalAttrs.version}/CommandCode-${finalAttrs.version}-amd64.deb";
    hash = "sha256-omFo9bpkbLHigQCOm+koJ6lLzDidraZcdcFLkJMNEi4=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libgbm
    nspr
    nss
    pango
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxcb
    libxkbcommon
    stdenv.cc.cc.lib
  ];

  # dpkg-deb only unpacks the payload; the upstream layout is
  # /opt/Command Code plus a desktop file and hicolor icons under /usr.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  # The Electron binary is already stripped and carries an appended payload
  # for the bundled app resources.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/opt" "$out/bin" "$out/share"
    cp -a "opt/Command Code" "$out/opt/command-code"

    # The .deb ships native modules for every supported OS/architecture.
    # Keep only the glibc x86_64 builds: autoPatchelfHook cannot patch the
    # ELF modules for other architectures, and the rest are dead weight.
    node_modules="$out/opt/command-code/resources/app/node_modules"
    rm -rf \
      "$node_modules"/@crosscopy/clipboard-darwin-* \
      "$node_modules"/@crosscopy/clipboard-win32-* \
      "$node_modules"/@crosscopy/clipboard-linux-arm64-* \
      "$node_modules"/@lydell/node-pty-darwin-* \
      "$node_modules"/@lydell/node-pty-win32-* \
      "$node_modules"/@lydell/node-pty-linux-arm64 \
      "$node_modules"/@parcel/watcher-darwin-* \
      "$node_modules"/@parcel/watcher-win32-* \
      "$node_modules"/@parcel/watcher-linux-arm64-* \
      "$node_modules"/@parcel/watcher-linux-x64-musl

    cp -a usr/share/icons "$out/share/icons"
    install -Dm644 "${desktopItem}/share/applications/command-code.desktop" \
      "$out/share/applications/command-code.desktop"

    makeWrapper "$out/opt/command-code/command-code" "$out/bin/command-code" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath ([ (lib.getLib stdenv.cc.cc) ] ++ runtimeLibraries)
      }" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --add-flags "--ozone-platform-hint=auto"

    runHook postInstall
  '';

  meta = {
    description = "Command Code desktop app, installed from the upstream Debian package";
    longDescription = ''
      Command Code is an Electron desktop client for the Command Code coding
      agent.  This package repackages the upstream x86_64 .deb for NixOS.
    '';
    homepage = "https://github.com/CommandCodeAI/desktop";
    changelog = "https://github.com/CommandCodeAI/desktop/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-code";
  };
})
