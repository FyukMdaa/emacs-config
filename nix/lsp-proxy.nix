{ pkgs }:
let
  lspProxyToml = (pkgs.formats.toml { }).generate "lsp-proxy.toml" {
    language-server = {
      nixd = {
        command = pkgs.lib.getExe pkgs.nixd;
      };
      clojure-lsp = {
        command = pkgs.lib.getExe pkgs.clojure-lsp;
      };
      docker-language-server = {
        command = pkgs.lib.getExe pkgs.dockerfile-language-server;
        args = [ "start" "--stdio" ];
      };
      typescript-language-server = {
        command = pkgs.lib.getExe pkgs.typescript-language-server;
        args = [ "--stdio" ];
      };
      vscode-json-language-server = {
        command = pkgs.lib.getExe' pkgs.vscode-langservers-extracted "vscode-json-language-server";
        args = [ "--stdio" ];
      };
      vscode-css-language-server = {
        command = pkgs.lib.getExe' pkgs.vscode-langservers-extracted "vscode-css-language-server";
        args = [ "--stdio" ];
      };
      yaml-language-server = {
        command = pkgs.lib.getExe pkgs.yaml-language-server;
        args = [ "--stdio" ];
      };
      taplo = {
        command = pkgs.lib.getExe pkgs.taplo;
        args = [ "lsp" "stdio" ];
      };
      bash-language-server = {
        command = pkgs.lib.getExe pkgs.bash-language-server;
        args = [ "start" ];
      };
      rust-analyzer = {
        command = pkgs.lib.getExe pkgs.rust-analyzer;
      };
    };
    language = [
      {
        name = "nix";
        file-types = [ "nix" ];
        roots = [ "flake.nix" ];
        language-servers = [ "nixd" ];
      }
      {
        name = "clojure";
        file-types = [ "clj" "cljs" "cljc" "edn" ];
        roots = [ "project.clj" "deps.edn" ];
        language-servers = [ "clojure-lsp" ];
      }
      {
        name = "dockerfile";
        file-types = [ "Dockerfile" "Containerfile" ];
        roots = [ "Dockerfile" "Containerfile" ];
        language-servers = [ "docker-language-server" ];
      }
      {
        name = "typescript";
        file-types = [ "ts" "tsx" ];
        roots = [ "package.json" "tsconfig.json" ];
        language-servers = [ "typescript-language-server" ];
      }
      {
        name = "javascript";
        file-types = [ "js" "jsx" ];
        roots = [ "package.json" ];
        language-servers = [ "typescript-language-server" ];
      }
      {
        name = "json";
        file-types = [ "json" ];
        roots = [ "." ];
        language-servers = [ "vscode-json-language-server" ];
      }
      {
        name = "css";
        file-types = [ "css" ];
        roots = [ "." ];
        language-servers = [ "vscode-css-language-server" ];
      }
      {
        name = "yaml";
        file-types = [ "yaml" "yml" ];
        roots = [ "." ];
        language-servers = [ "yaml-language-server" ];
      }
      {
        name = "toml";
        file-types = [ "toml" ];
        roots = [ "." ];
        language-servers = [ "taplo" ];
      }
      {
        name = "bash";
        file-types = [ "sh" ];
        roots = [ "." ];
        language-servers = [ "bash-language-server" ];
      }
      {
        name = "rust";
        file-types = [ "rs" ];
        roots = [ "Cargo.toml" ];
        language-servers = [ "rust-analyzer" ];
      }
    ];
  };
in
{
  inherit lspProxyToml;
  packages = with pkgs; [
    lsp-proxy
    nixd
    clojure-lsp
    dockerfile-language-server
    typescript-language-server
    vscode-langservers-extracted
    yaml-language-server
    taplo
    bash-language-server
    rust-analyzer
  ];
}
