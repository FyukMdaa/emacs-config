{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    #dotnet-sdk
    #omnisharp-roslyn
    nixd
    nodePackages.typescript-language-server
    rust-analyzer
    tree-sitter
    plemoljp-nf
    noto-fonts-cjk-sans
  ];
}
