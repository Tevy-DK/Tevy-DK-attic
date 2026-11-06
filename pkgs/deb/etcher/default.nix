{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  addDriverRunpath,
  # Electron / Chromium runtime libraries.  The executable links these
  # directly, so they belong in buildInputs for autoPatchelfHook.
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libgcc,
  libglvnd,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
  nspr,
  nss,
  pango,
  udev,
  # Runtime helpers.
  fontconfig,
  freetype,
  libnotify,
  libpulseaudio,
  libsecret,
  polkit,
  xdg-utils,
  gsettings-desktop-schemas,
  hicolor-icon-theme,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "balena-etcher";
  version = "2.1.9";

  # Upstream publishes a Debian package for amd64 only: there is no arm64
  # Linux build, so meta.platforms is restricted below.
  src = fetchurl {
    url = "https://github.com/balena-io/etcher/releases/download/v${finalAttrs.version}/balena-etcher_${finalAttrs.version}_amd64.deb";
    hash = "sha256-fg0OCYbl0PPZwDpMAAT5iRI1FQ4NqZ+gvDMtjAPxpMA=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    addDriverRunpath
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libgcc
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
    nspr
    nss
    pango
    udev
    fontconfig
    freetype
    libnotify
    libpulseaudio
    libsecret
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    runHook preUnpack
    # dpkg-deb --extract tries to preserve the setuid bit on chrome-sandbox,
    # which the Nix build sandbox refuses.  Drop special permission bits; the
    # binary is removed from the output below anyway.
    dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp -a usr/lib/balena-etcher "$out/lib/balena-etcher"

    # electron-builder leaves an absolute symlink into its build directory.
    rm -f "$out/lib/balena-etcher/balenaEtcher"

    # The Debian postinst makes chrome-sandbox setuid root.  A Nix store path
    # cannot carry that mode, and Chromium aborts when the helper exists but is
    # not usable instead of falling back to its namespace sandbox.  Removing
    # the helper keeps the sandbox enabled through unprivileged user namespaces
    # (available on NixOS) without passing --no-sandbox.
    rm -f "$out/lib/balena-etcher/chrome-sandbox"

    # Chromium dlopens libEGL rather than linking it, so the loader cannot use
    # the executable's RUNPATH for it.  libglvnd provides the dispatch library
    # and /run/opengl-driver/lib the Mesa vendor drivers.
    makeWrapper "$out/lib/balena-etcher/balena-etcher" "$out/bin/balena-etcher" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          libglvnd
          addDriverRunpath.driverLink
        ]
      }" \
      --prefix PATH : "${
        lib.makeBinPath [
          polkit
          xdg-utils
        ]
      }"

    install -Dm644 usr/share/applications/balena-etcher.desktop \
      "$out/share/applications/balena-etcher.desktop"
    install -Dm644 usr/share/pixmaps/balena-etcher.png \
      "$out/share/pixmaps/balena-etcher.png"

    runHook postInstall
  '';

  meta = {
    description = "Flash OS images to SD cards and USB drives, safely and easily";
    longDescription = ''
      balenaEtcher is an image flasher built with web technologies.  This
      package repackages the upstream Debian build for NixOS.
    '';
    homepage = "https://github.com/balena-io/etcher";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "balena-etcher";
    maintainers = [ ];
  };
})
