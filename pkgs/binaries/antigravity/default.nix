{
  lib,
  stdenv,
  fetchurl,
  asar,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  copyDesktopItems,
  makeDesktopItem,
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
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxtst,
  nspr,
  nss,
  pango,
  systemdLibs,
  # Runtime helpers.
  libGL,
  libnotify,
  libpulseaudio,
  libsecret,
  pipewire,
  gsettings-desktop-schemas,
  hicolor-icon-theme,
}:

let
  # Google publishes one tarball per architecture under a release id of the
  # form "<version>-<build>".
  arch = if stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
  hash =
    if stdenv.hostPlatform.isAarch64 then
      "sha256-jevgvhGpqJq0ShAjPj/e+46K0ltc7+tY8kV9GNCrkHA="
    else
      "sha256-LTPbKCsemzx1gsFA2rnoaEjxs3oFv6Sh3/f0TeG/ME8=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "antigravity";
  version = "2.35.2";
  build = "4585983447007232";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-hub/${finalAttrs.version}-${finalAttrs.build}/linux-${arch}/Antigravity.tar.gz";
    inherit hash;
  };

  nativeBuildInputs = [
    asar
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
    copyDesktopItems
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
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxrender
    libxtst
    nspr
    nss
    pango
    systemdLibs
    stdenv.cc.cc.lib
    gsettings-desktop-schemas
    hicolor-icon-theme
  ];

  # Electron dlopen()s these instead of linking them, so they never appear in
  # a DT_NEEDED entry that autoPatchelfHook could resolve.
  runtimeDependencies = [
    libGL
    libnotify
    libpulseaudio
    libsecret
    pipewire
  ];

  dontWrapGApps = true;
  # The Electron payload is already stripped.
  dontStrip = true;

  desktopItems = [
    (makeDesktopItem {
      name = "antigravity";
      desktopName = "Antigravity";
      comment = "Desktop environment for managing multiple autonomous agents across independent projects";
      exec = "antigravity %U";
      icon = "antigravity";
      categories = [ "Development" ];
      mimeTypes = [ "x-scheme-handler/antigravity" ];
      startupWMClass = "Antigravity";
    })
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/antigravity"
    cp -a . "$out/lib/antigravity/"
    app="$out/lib/antigravity"

    # The Debian build makes chrome-sandbox setuid root.  A Nix store path
    # cannot carry that mode, and Chromium aborts when the helper exists but
    # is unusable, so remove it and let Electron fall back to the namespace
    # sandbox instead of passing --no-sandbox.
    rm -f "$app/chrome-sandbox"

    # The tarball ships no desktop entry or icon; both live inside app.asar.
    ${asar}/bin/asar extract-file "$app/resources/app.asar" icon.png
    install -Dm644 icon.png "$out/share/icons/hicolor/512x512/apps/antigravity.png"

    runHook postInstall
  '';

  postFixup = ''
    # Chromium dlopen()s libEGL/libGL instead of linking them, so the loader
    # cannot use the executable's RUNPATH.  libglvnd provides the dispatch
    # library and driverLink the Mesa vendor drivers.
    makeWrapper "$out/lib/antigravity/antigravity" "$out/bin/antigravity" \
      ''${gappsWrapperArgs[@]} \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          libGL
          addDriverRunpath.driverLink
        ]
      }"
  '';

  meta = {
    description = "Google Antigravity desktop application";
    longDescription = ''
      Agent-first desktop application by Google, repackaged from the
      upstream Linux tarball.
    '';
    homepage = "https://antigravity.google";
    changelog = "https://antigravity.google/changelog";
    downloadPage = "https://antigravity.google/download";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "antigravity";
  };
})
