{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  asar,
  autoPatchelfHook,
  makeWrapper,
  qt6,
  wrapGAppsHook3,
  writeShellApplication,
  # Electron / Chromium runtime libraries.  The executable links these
  # directly, so they belong in buildInputs for autoPatchelfHook.
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  dconf,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libgbm,
  libnotify,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  systemdLibs,
  tpm2-tss,
  # Runtime helpers: the bundled launcher runs workspace commands through
  # bubblewrap and shells out to git and xdg-open.
  bubblewrap,
  coreutils,
  flock,
  gitMinimal,
  libGL,
  libpulseaudio,
  libsecret,
  lsb-release,
  pipewire,
  vulkan-loader,
  xdg-utils,
}:

let
  arch = if stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
  hash =
    if stdenv.hostPlatform.isAarch64 then
      "sha256-xcWqCQlo73oosnyu09AzdIidfIJQdogU60yuXZudmiU="
    else
      "sha256-S0Q7xVc1ChsZO8LxuuIHyeo8n7XZT3yUpdPbqotVI1I=";

  # Electron rewrites the bundled plugin manifests at runtime, so that
  # directory is copied into the user cache while everything else is
  # symlinked from the immutable store path.
  launcher = writeShellApplication {
    name = "chatgpt-launcher";
    runtimeInputs = [
      coreutils
      flock
    ];
    text = ''
      : "''${CHATGPT_EXECUTABLE:?}"
      : "''${CHATGPT_RESOURCES_SOURCE:?}"
      : "''${CHATGPT_RESOURCES_CACHE_KEY:?}"

      cacheHome="''${XDG_CACHE_HOME:-''${HOME:?XDG_CACHE_HOME and HOME are unset}/.cache}"
      cacheRoot="$cacheHome/chatgpt/bundled-plugins-v2"
      resourcesPath="$cacheRoot/$CHATGPT_RESOURCES_CACHE_KEY"

      mkdir -p "$cacheRoot"
      exec {initLockFd}> "$cacheRoot.lock"
      flock --exclusive "$initLockFd"

      # A concurrent launch may have reclaimed the directory; verify that the
      # lock still refers to the path we hold.
      while true; do
        mkdir -p "$resourcesPath"
        if exec {resourcesLockFd}< "$resourcesPath"; then
          flock --shared "$resourcesLockFd"
          [[ "$resourcesPath" -ef "/proc/self/fd/$resourcesLockFd" ]] && break
          exec {resourcesLockFd}>&-
        else
          [[ ! -d "$resourcesPath" ]] || exit 1
        fi
      done

      if [[ ! -f "$resourcesPath/.complete" ]]; then
        ln -sfn -t "$resourcesPath" \
          "$CHATGPT_RESOURCES_SOURCE"/{codex,codex-code-mode-host,cua_node,native,rg,tectonic}
        mkdir -p "$resourcesPath/plugins"
        cp -RT --preserve=mode "$CHATGPT_RESOURCES_SOURCE/plugins" "$resourcesPath/plugins"
        chmod -R u+w "$resourcesPath/plugins"
        sync --file-system "$resourcesPath"
        touch "$resourcesPath/.complete"
        sync --file-system "$resourcesPath"
      fi
      exec {initLockFd}>&-

      export CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH="$resourcesPath"

      # Follow the NixOS convention for opting into native Wayland.
      waylandFlags=()
      if [[ -n "''${NIXOS_OZONE_WL:-}" && -n "''${WAYLAND_DISPLAY:-}" ]]; then
        waylandFlags=(
          --ozone-platform=wayland
          --enable-features=WaylandWindowDecorations
          --enable-wayland-ime=true
        )
      fi

      exec "$CHATGPT_EXECUTABLE" "''${waylandFlags[@]}" "$@"
    '';
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "chatgpt";
  version = "26.1111.21308";

  # Only OpenAI's signed Linux repository publishes the desktop application;
  # there is no GitHub release to track.
  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${finalAttrs.version}_${arch}.deb";
    inherit hash;
  };

  nativeBuildInputs = [
    dpkg
    asar
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    dconf
    expat
    gdk-pixbuf
    glib
    gtk3
    libgbm
    libnotify
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    qt6.qtbase
    stdenv.cc.cc.lib
    systemdLibs
    tpm2-tss
  ];

  # Chromium dlopen()s these instead of linking them, so they never appear in
  # a DT_NEEDED entry that autoPatchelfHook could resolve.
  runtimeDependencies = [
    libGL
    libnotify
    libpulseaudio
    libsecret
    pipewire
    vulkan-loader
  ];

  dontWrapGApps = true;
  dontWrapQtApps = true;
  # The native payload ships pre-stripped; re-stripping adds nothing.
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp -a usr/lib/chatgpt "$out/lib/chatgpt"
    resources="$out/lib/chatgpt/resources"

    # Unused Qt 5 fallback shim; the runtime only loads the Qt 6 one.
    rm -f "$out/lib/chatgpt/libqt5_shim.so"

    # app.asar pins detect-libc's answer, which reads the PT_INTERP offset that
    # autoPatchelfHook moves out of reach; Electron's process.report fallback
    # then aborts the main process.
    unpackedDirs=$(
      find "$resources/app.asar.unpacked/node_modules" \
        -mindepth 1 -maxdepth 2 \
        ! -name '@*' -printf '%P\n' -prune |
        paste -sd,
    )
    ${asar}/bin/asar extract "$resources/app.asar" app
    substituteInPlace app/node_modules/@parcel/watcher/index.js \
      --replace-fail 'const family = familySync();' "const family = '${stdenv.hostPlatform.libc}';"
    rm -rf "$resources/app.asar" "$resources/app.asar.unpacked"
    ${asar}/bin/asar pack app "$resources/app.asar" \
      --unpack-dir "node_modules/{$unpackedDirs}"
    rm -rf app

    # Keep only the native prebuild for this platform and architecture;
    # autoPatchelfHook would otherwise rewrite foreign and musl ELFs too.
    find "$resources" -type d -name prebuilds -print0 |
      while IFS= read -r -d "" prebuildsPath; do
        find "$prebuildsPath" -mindepth 1 -maxdepth 1 \
          ! -name "*${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}" \
          -exec rm -rf -- {} +
      done
  ''
  + lib.optionalString stdenv.hostPlatform.isGnu ''
    find "$resources" -type f -name '*.musl.node' -delete
  ''
  + ''

    install -Dm755 ${launcher}/bin/chatgpt-launcher "$out/bin/chatgpt"
    install -Dm644 usr/share/applications/chatgpt.desktop \
      "$out/share/applications/chatgpt.desktop"
    install -Dm644 usr/share/pixmaps/chatgpt.png "$out/share/pixmaps/chatgpt.png"
    install -Dm644 usr/share/metainfo/com.openai.chatgpt.metainfo.xml \
      "$out/share/metainfo/com.openai.chatgpt.metainfo.xml"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/chatgpt" \
      ''${gappsWrapperArgs[@]} \
      ''${qtWrapperArgs[@]} \
      --set CHATGPT_EXECUTABLE "$out/lib/chatgpt/ChatGPT" \
      --set CHATGPT_RESOURCES_SOURCE "$out/lib/chatgpt/resources" \
      --set CHATGPT_RESOURCES_CACHE_KEY "''${out##*/}" \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          coreutils
          gitMinimal
          lsb-release
          xdg-utils
        ]
      }
  '';

  meta = {
    description = "ChatGPT desktop application by OpenAI, repackaged from the official Debian package";
    homepage = "https://developers.openai.com/codex/app";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "chatgpt";
  };
})
