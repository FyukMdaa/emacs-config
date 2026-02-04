{
  config,
  lib,
  pkgs,
  ...
}:
let
  # 使用したいTree-sitterの文法リストを定義
  # ここで宣言した言語のGrammarがNixから提供されます
  my-treesit-grammars = with pkgs.tree-sitter-grammars; [
    tree-sitter-nix       # Nix
    tree-sitter-rust      # Rust
    tree-sitter-go        # Go
    tree-sitter-bash      # Bash
    tree-sitter-html      # HTML
    tree-sitter-css       # CSS
    tree-sitter-javascript
    tree-sitter-json
    tree-sitter-python
    tree-sitter-toml
    tree-sitter-yaml
    tree-sitter-typescript
    tree-sitter-tsx
  ];

  # Grammarをまとめたパッケージを作成
  treesit-grammar-pkg = pkgs.tree-sitter-grammars.with-grammars (p: my-treesit-grammars);

in
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
    python3 # eglot-booster 用

    # --- ここにTree-sitter Grammarsを追加 ---
    treesit-grammar-pkg
  ];

  # EmacsがGrammarを見つけられるように環境変数を設定
  home.sessionVariables = {
    LD_LIBRARY_PATH = "${treesit-grammar-pkg}/lib:$LD_LIBRARY_PATH";
    # 念のためEMACSNATIVELOADPATHにも追加（.elnファイル用）
    EMACSNATIVELOADPATH = "${treesit-grammar-pkg}/lib:$EMACSNATIVELOADPATH";
  };
}
