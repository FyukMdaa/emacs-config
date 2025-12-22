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
          emacsPackage = pkgs.emacs-git;
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

      in {
        packages.default = package;

        # Home Manager
        homeModules.twist = {
          imports = [
            inputs.twist.homeModules.emacs-twist
          ];
          programs.emacs-twist = {
            enable = true;
            config = package;
            createInitFile = true;
          };
        };

        # ロックファイルの生成
        apps = package.makeApps {
          lockDirName = "lock";
        };
      });
}
