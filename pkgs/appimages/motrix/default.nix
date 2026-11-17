{
  lib,
  stdenv,
  appimageTools,
  fetchurl,
}:

let
  isAarch64 = stdenv.hostPlatform.isAarch64;
  assetArch = if isAarch64 then "arm64" else "x86_64";
  hash =
    if isAarch64 then
      "sha256-FJj4Lk5Eb8FvbMO27xxqjB/EzjIAQRsGtwLMYdJvbS0="
    else
      "sha256-O2w0UC+X0TYocIZDDc9oKkWTTkMNEr9gjaxr4lJFWJc=";
in
appimageTools.wrapType2 (finalAttrs: {
  pname = "motrix";
  version = "2.4.3";

  src = fetchurl {
    url = "https://github.com/agalwood/Motrix/releases/download/v${finalAttrs.version}/Motrix-${finalAttrs.version}-${assetArch}.AppImage";
    hash = hash;
  };

  # The AppImage bundles its own desktop entry and icon theme; install both so
  # launchers do not need to know about the FHS wrapper.
  extraInstallCommands = ''
    install -Dm444 ${finalAttrs.contents}/motrix.desktop -t "$out/share/applications"
    cp -r ${finalAttrs.contents}/usr/share/icons "$out/share"

    substituteInPlace "$out/share/applications/motrix.desktop" \
      --replace-fail 'Exec=AppRun' 'Exec=motrix'
  '';

  meta = {
    description = "Full-featured download manager with HTTP, FTP, BitTorrent and Magnet support";
    homepage = "https://motrix.app";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "motrix";
    maintainers = [ ];
  };
})
