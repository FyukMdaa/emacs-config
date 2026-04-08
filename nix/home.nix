homeManagerModules.default = { lib, pkgs, config, ... }:
  let
    cfg = config.programs.fyukmdaa-emacs;
  in {
    imports = [ inputs.twist.homeModules.emacs-twist ];

    options.programs.fyukmdaa-emacs = {
      enable = lib.mkEnableOption "FyukMdaa's Emacs configuration";
    };

    config = lib.mkIf cfg.enable {
      programs.emacs-twist = {
        enable = true;
        config = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.env;
        earlyInitFile = lib.mkDefault (
          (import nixpkgs {
            system = pkgs.stdenv.hostPlatform.system;
            overlays = [ inputs.org-babel.overlays.default ];
          }).tangleOrgBabelFile "early-init.el" ./early-init.org {}
        );
        createManifestFile = true;
      };

      home.packages = with pkgs; [
        nixd
        nodePackages.typescript-language-server
        rust-analyzer
        plemoljp-nf
        noto-fonts-cjk-sans
        python3
      ];
    };
  };
