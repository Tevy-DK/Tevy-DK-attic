{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    # Release discovery and downloads.
    curl
    wget
    jq
    gh
    git

    # Hash prefetching and inspection.
    nix-prefetch-scripts
    binutils
    file
    patchelf
    python3

    # Debian package unpacking and dependency inspection.
    dpkg

    # RPM / AppImage / miscellaneous archive handling.
    rpm
    squashfsTools
    cpio
    unzip
    zstd
    xz
    gzip
    bzip2

    # Nix formatting and GUI smoke testing.
    nixfmt
    xvfb-run
  ];

  shellHook = ''
    echo "Tevy-DK-attic dev shell: use 'nix build .#<pkg>' and inspect upstream releases with 'gh release view'."
  '';
}
