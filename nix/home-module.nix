{ self, twist }:
{ config, lib, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [ twist.homeModules.emacs-twist ];

  config = lib.mkIf config.programs.emacs-twist.enable {
    programs.emacs-twist = {
      config = self.packages.${system}.emacsEnv;
      earlyInitFile = self.packages.${system}.earlyInitFile;
      createInitFile = true;
    };
  };
}
