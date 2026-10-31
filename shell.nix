{
  pkgs ? import <nixpkgs> { },
}:
import ./devshell.nix { inherit pkgs; }
