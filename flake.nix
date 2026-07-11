{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    twist.url = "github:emacs-twist/twist.nix";
    org-babel.url = "github:emacs-twist/org-babel";
    fmpkgs.url = "github:fyukmdaa/fmnixpkgs";

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
      fmpkgs,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            org-babel.overlays.default
            fmpkgs.overlays.default
          ];
        };
        lib = pkgs.lib;

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

          # パッケージのオーバーライド設定を外部ファイルから読み込む
          inputOverrides = import ./nix/override.nix { inherit pkgs; };

          # パッケージの取得先。
          registries = import ./nix/registries.nix inputs;

          # tree-sitter
          extraSiteStartElisp = ''
            (add-to-list 'treesit-extra-load-path "${
              pkgs.emacs.pkgs.treesit-grammars.with-grammars (
                _: builtins.filter
                  (grammar: ((grammar.meta or {}).broken or null) != true)
                  pkgs.tree-sitter.allGrammars
              )
            }/lib/")
          '';
        };

        # nix run で利用するフォント。
        fontPackages = with pkgs; [
        	sfmono-square
        	nerd-fonts.symbols-only
        ];

        # 上記のフォントを追加したfontconfig 設定
        fontsConf = pkgs.makeFontsConf { fontDirectories = fontPackages; };

        # `nix run .` で起動できるようにするラッパー。  
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
              --add-flags --init-directory="$out/share/emacs-config" \
              --set FONTCONFIG_FILE ${fontsConf}
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
      homeModules.default = import ./nix/home-module.nix { inherit self twist; };
    };
}
