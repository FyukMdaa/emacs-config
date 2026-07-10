inputs: [
  {
  	type = "melpa";
  	path = ../recipes;
  }
  {
    name = "melpa";
    type = "melpa";
    path = inputs.melpa.outPath + "/recipes";
  }
  {
    # auto-sync-only = true は「Emacs 本体のリポジトリと同期されている
    # (= core にマージ済みで履歴を共有している) パッケージだけ」を対象に
    # する指定。
    name = "gnu";
    type = "elpa";
    path = inputs.elpa.outPath + "/elpa-packages";
    auto-sync-only = true;
  }
  {
    name = "gnu-devel";
    type = "archive";
    url = "https://elpa.gnu.org/devel/";
  }
  {
    name = "nongnu";
    type = "elpa";
    path = inputs.nongnu.outPath + "/elpa-packages";
  }
  {
    name = "nongnu-devel";
    type = "archive";
    url = "https://elpa.nongnu.org/nongnu-devel/";
  }
  {
    # Emacsmirror 上の git submodule 一覧 (.gitmodules) から
    # MELPA 形式のレシピを自動生成して検索する。
    name = "emacsmirror";
    type = "gitmodules";
    path = inputs.epkgs.outPath + "/.gitmodules";
  }
]
