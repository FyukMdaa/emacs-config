{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    
    twist.url = "github:emacs-twist/twist.nix";
    
    org-babel.url = "github:emacs-twist/org-babel";

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

  outputs = {
    self,
      nixpkgs,
      flake-utils,
      emacs-overlay,
      ...
  } @ inputs: flake-utils.lib.eachDefaultSystem
        (system: let
          inherit (nixpkgs) lib;
          
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              inputs.org-babel.overlays.default
              emacs-overlay.overlays.default
            ];
          };

          profile = {
            lockDir = ./lock;
            initFiles = [
              (pkgs.tangleOrgBabelFile "init.el" ./init.org {})
            ];
            emacsPackage = pkgs.emacs-pgtk;
            exportManifest = true;
            extraPackages = [ ];
            extraRecipeDir = ./recipes;
            extraInputOverrides = {};
          };

          package = (inputs.twist.lib.makeEnv {
            inherit pkgs;
            inherit (profile) emacsPackage lockDir initFiles;
            registries = (import ./nix/registries.nix inputs) ++ [
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

          homeModules.twist = {
            imports = [
              inputs.twist.homeModules.emacs-twist
            ];

            programs.emacs-twist = {
              config = lib.mkDefault package;
              earlyInitFile = lib.mkDefault earlyInitEl;
            };
          };
          
          apps = package.makeApps {
            lockDirName = "lock";
          };
        });
}
