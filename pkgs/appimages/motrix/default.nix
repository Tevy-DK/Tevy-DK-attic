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
      "sha256-v9e3l8k53Zyspir1tquJC1E41apSIX+4odTMOtvd0Nk="
    else
      "sha256-762PpaRusgx+pAo+F0ju06V86Yll9ODosoCgihvgtY8=";
in
appimageTools.wrapType2 (finalAttrs: {
  pname = "motrix";
  version = "2.3.0";

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
