{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    twist.url = "github:emacs-twist/twist.nix";
    org-babel.url = "github:emacs-twist/org-babel";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    
    # Archive inputs (no need to process as flakes)
    elpa = { url = "github:elpa-mirrors/elpa"; flake = false; };
    melpa = { url = "github:melpa/melpa"; flake = false; };
    nongnu = { url = "github:elpa-mirrors/nongnu"; flake = false; };
    epkgs = { url = "github:emacsmirror/epkgs"; flake = false; };
  };

  outputs = { self, nixpkgs, flake-utils, emacs-overlay, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            inputs.org-babel.overlays.default
            emacs-overlay.overlays.default
          ];
        };

        # Tangle org files to elisp
        initFile = pkgs.tangleOrgBabelFile "init.el" ./init.org {};
        earlyInitFile = pkgs.tangleOrgBabelFile "early-init.el" ./early-init.org {};

        # Main Emacs environment
        emacsEnv = inputs.twist.lib.makeEnv {
          inherit pkgs;
          emacsPackage = pkgs.emacs-pgtk;
          lockDir = ./lock;
          initFiles = [ initFile ];
          exportManifest = true;
          registries = (import ./nix/registries.nix inputs) ++ [
            {
              name = "custom";
              type = "melpa";
              path = ./recipes;
            }
          ];
        };

        # Emacs wrapper with both init files
        emacsWithConfig = pkgs.writeShellScriptBin "emacs" ''
          initdir="$(mktemp --tmpdir -d emacs-XXX)"
          trap "rm -rf '$initdir'" EXIT
          
          ln -s ${initFile} "$initdir/init.el"
          ln -s ${earlyInitFile} "$initdir/early-init.el"
          ln -s ${emacsEnv}/share/twist-manifest.json "$initdir/twist-manifest.json"

          exec ${emacsEnv}/bin/emacs --init-directory="$initdir" "$@"
        '';
      in
      {
        packages = {
          default = emacsWithConfig;
          env = emacsEnv;
          init = initFile;
          early-init = earlyInitFile;
        };

        apps = emacsEnv.makeApps {
          lockDirName = "lock";
        };
        
        homeModules.twist = { config, lib, ... }: {
          imports = [ inputs.twist.homeModules.emacs-twist ];

          programs.emacs-twist = {
            enable = true;

            directory = ".local/share/emacs";
            
            # twist manifest
            createManifestFile = true;

            # flake.nix で定義した環境
            config = emacsEnv;

            # early-initファイルを指定
            earlyInitFile = earlyInitFile;

            # サービス統合を有効化
            emacsclient.enable = true;
            serviceIntegration.enable = lib.mkDefault true;
          };

          home.packages = with pkgs; [
            
          ];

          # デスクトップファイルの生成
          services.emacs.client.enable = config.programs.emacs-twist.serviceIntegration.enable;
        };
      }
    );
}
