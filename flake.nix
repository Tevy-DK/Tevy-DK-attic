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
      # chatgpt is proprietary, so the flake's own outputs have to accept
      # unfree licenses.  Consumers of the overlay keep their own setting.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      packages = forAllSystems (system: {
        omp = (pkgsFor system).callPackage ./pkgs/binaries/omp { };
        chatgpt = (pkgsFor system).callPackage ./pkgs/deb/chatgpt { };
        sjmcl = (pkgsFor system).callPackage ./pkgs/binaries/sjmcl { };
        motrix = (pkgsFor system).callPackage ./pkgs/appimages/motrix { };
        etcher = (pkgsFor system).callPackage ./pkgs/deb/etcher { };
      });

      overlays.default =
        final: prev:
        prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
          omp = final.callPackage ./pkgs/binaries/omp { };
          chatgpt = final.callPackage ./pkgs/deb/chatgpt { };
          sjmcl = final.callPackage ./pkgs/binaries/sjmcl { };
          motrix = final.callPackage ./pkgs/appimages/motrix { };
          etcher = final.callPackage ./pkgs/deb/etcher { };
        };

      devShells = forAllSystems (system: {
        default = import ./devshell.nix { pkgs = pkgsFor system; };
      });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
