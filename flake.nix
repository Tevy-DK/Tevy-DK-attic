{
  description = "Tevy-DK's binary-only Nix package attic";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (system: {
        omp = (pkgsFor system).callPackage ./pkgs/binaries/omp { };
        codex = (pkgsFor system).callPackage ./pkgs/binaries/codex { };
        sjmcl = (pkgsFor system).callPackage ./pkgs/binaries/sjmcl { };
        moonlight-web = (pkgsFor system).callPackage ./pkgs/binaries/moonlight-web { };
        motrix = (pkgsFor system).callPackage ./pkgs/appimages/motrix { };
        etcher = (pkgsFor system).callPackage ./pkgs/deb/etcher { };
      });

      overlays.default =
        final: prev:
        prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
          omp = final.callPackage ./pkgs/binaries/omp { };
          codex = final.callPackage ./pkgs/binaries/codex { };
          sjmcl = final.callPackage ./pkgs/binaries/sjmcl { };
          moonlight-web = final.callPackage ./pkgs/binaries/moonlight-web { };
          motrix = final.callPackage ./pkgs/appimages/motrix { };
          etcher = final.callPackage ./pkgs/deb/etcher { };
        };

      devShells = forAllSystems (system: {
        default = import ./devshell.nix { pkgs = pkgsFor system; };
      });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
