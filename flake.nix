{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    twist.url = "github:emacs-twist/twist.nix";
    org-babel.url = "github:emacs-twist/org-babel";

    melpa = {
      url = "github:melpa/melpa";
      flake = false;
    };
    elpa = {
      url = "github:elpa-mirrors/elpa";
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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      twist,
      org-babel,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ org-babel.overlays.default ];
        };

        emacsPackage = pkgs.emacs-pgtk;

        # early-init.org / init.org をtangleする。
        earlyInitFile = pkgs.tangleOrgBabelFile "early-init.el" ./early-init.org { };
        initFile = pkgs.tangleOrgBabelFile "init.el" ./init.org { };

        emacsEnv = twist.lib.makeEnv {
          inherit pkgs emacsPackage;

          exportManifest = true;
          nativeCompileAheadDefault = true;

          initFiles = [ initFile ];
          lockDir = ./lock;

          # setup.el を使用する
          initParser = twist.lib.parseSetup { inherit lib; } { };
          extraPackages = [ "setup" ];

          # パッケージの取得先。
          registries = import ./nix/registries.nix inputs;

          # tree-sitter
          extraSiteStartElisp = ''
            (add-to-list 'treesit-extra-load-path "${
              pkgs.callPackage (import ./treesit-grammars.nix { inherit inputs; }) { }
            }/lib/")
          '';
        };

        package = pkgs.runCommandLocal "emacs-config"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            meta.mainProgram = "emacs";
          }
          ''
            mkdir -p "$out/bin" "$out/share/emacs-config"
            cp ${earlyInitFile} "$out/share/emacs-config/early-init.el"
            cp ${initFile} "$out/share/emacs-config/init.el"

            makeWrapper ${emacsEnv}/bin/emacs "$out/bin/emacs" \
              --add-flags --init-directory="$out/share/emacs-config"
          '';
      in
      {
        packages.default = package;
        packages.emacsEnv = emacsEnv;
        packages.earlyInitFile = earlyInitFile;

        apps = emacsEnv.makeApps { lockDirName = "lock"; };
      }
    )
    // {
      homeModules.default = import ./home-module.nix { inherit self twist; };
    };
}
