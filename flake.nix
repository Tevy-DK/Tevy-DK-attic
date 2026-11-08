{
  description = "Tevy-DK's binary-only Nix package attic";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # dsh-desktop 没有可直接安装的 Release 二进制（上游只发自解压 Electron
    # 包，内含 setuid helper，无法在 Nix store 里保留），社区 flake 用 nixpkgs
    # electron 重建了外壳并复用共享 dsh runtime。这里直接转发，不再自己实现。
    deepseek-harness = {
      url = "github:moraxyc/deepseek-harness.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # 上游 flake 只在自己支持的平台上提供该属性；缺失时从输出里省略，
      # 而不是让整个 flake 求值失败。
      dshDesktop =
        system:
        let
          upstream = inputs.deepseek-harness.packages.${system} or { };
        in
        upstream.dsh-desktop-unofficial or null;
      optionalDshDesktop =
        system:
        nixpkgs.lib.optionalAttrs (dshDesktop system != null) {
          dsh-desktop = dshDesktop system;
        };
    in
    {
      packages = forAllSystems (
        system:
        {
          omp = (pkgsFor system).callPackage ./pkgs/binaries/omp { };
          codex = (pkgsFor system).callPackage ./pkgs/binaries/codex { };
          sjmcl = (pkgsFor system).callPackage ./pkgs/binaries/sjmcl { };
          motrix = (pkgsFor system).callPackage ./pkgs/appimages/motrix { };
          etcher = (pkgsFor system).callPackage ./pkgs/deb/etcher { };
        }
        // optionalDshDesktop system
      );

      overlays.default =
        final: prev:
        prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux (
          {
            omp = final.callPackage ./pkgs/binaries/omp { };
            codex = final.callPackage ./pkgs/binaries/codex { };
            sjmcl = final.callPackage ./pkgs/binaries/sjmcl { };
            motrix = final.callPackage ./pkgs/appimages/motrix { };
            etcher = final.callPackage ./pkgs/deb/etcher { };
          }
          // optionalDshDesktop prev.stdenv.hostPlatform.system
        );

      devShells = forAllSystems (system: {
        default = import ./devshell.nix { pkgs = pkgsFor system; };
      });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
