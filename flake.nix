{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    twist.url = "github:emacs-twist/twist.nix";
    org-babel.url = "github:emacs-twist/org-babel";

    # Emacsパッケージ
    elpa = {
      url = "github:elpa-mirrors/elpa";
      flake = false;
    };
    melpa = {
      url = "github:melpa/melpa";
      flake = false;
    };
    nongnu = {
      url = "github:elpa-mirrors/nongnu";
      flake = false;
    };
    epkgs = {
      url = "github:emacsmirror/epkgs";
      flake = false;
    };
    emacs-overlay.url = "github:nix-community/emacs-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            inputs.org-babel.overlays.default
            inputs.emacs-overlay.overlay
          ];
        };

        # profileを指定
        profile = {
          lockDir = ./lock;
          initFiles = [
            # init.orgをinit.elとして読み込み
            (pkgs.tangleOrgBabelFile "init.el" ./init.org {})
          ];
          emacsPackage = pkgs.emacs-pgtk;
          extraRecipeDir = ./recipes;
        };

        # Twist.nix
        package = (inputs.twist.lib.makeEnv {
          inherit pkgs;
          inherit (profile) emacsPackage lockDir initFiles;
          registries = (import ./nix/registries.nix { inherit inputs; }) ++ [
            {
              name = "custom";
              type = "melpa";
              path = profile.extraRecipeDir;
            }
          ];
        });

	    earlyInitEl = (pkgs.tangleOrgBabelFile "early-init.el" ./early-init.org {});
	    
      in {
        packages.default = package;

		earlyInitEl = earlyInitEl;

        # Home Manager
        homeModules.twist = { lib, ... }: {
          imports = [
            inputs.twist.homeModules.emacs-twist
          ];
          programs.emacs-twist = {
            enable = true;
            config = package;
            earlyInitFile = lib.mkDefault earlyInitEl;
            createInitFile = true;
          };
        };

        # ロックファイルの生成
        apps = package.makeApps {
          lockDirName = "lock";
        };
      });
}
