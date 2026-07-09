# twist.nix 詳細ガイド

> **twist.nix** は Akirak によって開発された、Nix を用いた Emacs Lisp パッケージのソースベースビルド機構です。
> Nix のエコシステム内で Emacs 本体・ELisp パッケージ・依存ツール（tree-sitter 等）を統一的に管理し、home-manager モジュールとしても利用可能です。
> 
> 

**ステータス**: Alpha（機能は安定動作していますが、API は将来変更される可能性があります）

---

## 目次

1. 概要と設計思想
2. 他ツールとの比較
3. アーキテクチャ
4. インストール・セットアップ
5. flake.nix の書き方
6. makeEnv の全オプション
7. レジストリ（registries）の種類と設定
8. init ファイルのパーサー
9. home-manager モジュール
10. ロックファイルの仕組み
11. パッケージビルドの内部動作
12. パッケージのオーバーライド
13. ラッパーの仕組み
14. トラブルシューティングとTips
15. 設定例
16. リファレンス: ファイル構成
---

## 1. 概要と設計思想

`twist.nix` は `package-build`（MELPA のビルドシステム）の Nix 再実装です。従来の Nix/NixOS における `emacsWithPackages`（nixpkgs の Emacs ラッパー）が**事前ビルド済みのアーカイブ**を取得するのに対し、`twist.nix` は**ソースリポジトリから直接ビルド**を行います。

### 主要な特徴

* **高速起動**: パッケージをフラットなディレクトリにマッピングするだけであるため、ビルド時間が短く、起動時のロードパス解決も高速です。


* **flake.lock によるバージョン管理**: パッケージバージョンを `flake.lock` で追跡できるため、個別パッケージのロックや更新が容易に行えます。


* **init ファイルからの自動発見**: `use-package` や `setup.el` の設定を読み取り、必要なパッケージを自動的に特定します。


* **複数レジストリ対応**: MELPA、ELPA（GNU/NonGNU）、EmacsMirror、カスタムアーカイブなどに対応しています。


* **straight.el ライクなカスタムパッケージ**: MELPA レシピ形式を利用して、カスタムパッケージを定義することが可能です。



### emacs-twist プロジェクト全体の構成

| コンポーネント | 役割 | 相当する既存ツール |
| --- | --- | --- |
| **twist.nix**（本リポジトリ） | ビルド機構

 | package-build

 |
| [twist.el](https://github.com/emacs-twist/twist.el) + [nix3.el](https://github.com/emacs-twist/nix3.el) | Emacs パッケージマネージャフロントエンド

 | straight.el, borg

 |
| [nomake](https://www.google.com/search?q=https://github.com/emacs-twist/nomake) + [rice](https://github.com/emacs-twist/rice-config) | パッケージ開発

 | cask

 |

---

## 2. 他ツールとの比較

### vs `emacsWithPackages`（nixpkgs）

| 特徴 | twist.nix | emacsWithPackages |
| --- | --- | --- |
| **ソース** | 上流リポジトリからビルド

 | 事前ビルド済みアーカイブ

 |
| **バージョン管理** | `flake.lock` で個別ロック

 | nixpkgs リビジョンに依存

 |
| **カスタムパッケージ** | MELPA レシピで簡単追加

 | nixpkgs overlay が必要

 |
| **起動速度** | 高速（フラットマッピング）

 | やや遅い場合あり

 |
| **IFD (Import From Derivation)** | 可能な限り回避する設計

 | 多く発生しがち

 |

### vs straight.el / borg.el

| 特徴 | twist.nix | straight.el / borg |
| --- | --- | --- |
| **再現性** | 完全（Nix が保証）

 | ロックファイルによる

 |
| **ビルド** | Nix サンドボックス内

 | ユーザー環境

 |
| **複数マシン** | `nix build` 一発

 | 追加設定が必要

 |
| **パッケージ管理** | twist.el（開発中）

 | straight.el / borg 自体

 |

---

## 3. アーキテクチャ

`twist.nix` のデータフローは以下のようになります。

```
init.el / init.org
    │
    ▼ (initParser)
パッケージ名のリスト
    │
    ▼ (registries + lock files)
パッケージメタデータ（src, version, 依存関係等）
    │
    ▼ (data/default.nix: 依存解決)
 concrete package set (packageInputs)
    │
    ├─▶ elispPackages/*  （各パッケージの drv）
    ├─▶ emacsWrapper      （最終的な Emacs ラッパー）
    └─▶ generateLockDir  （ロックファイル生成コマンド）

```

### コアコンポーネントの役割

以下に各ファイルの主要な役割を示します。

* `lib/default.nix`: 公開 API (`makeEnv`, `parseSetup`, `parseUsePackages`, `buildElispPackage`)。


* `pkgs/emacs/default.nix`: `makeEnv` の実体。設定全体を組み立てるスコープ。


* `pkgs/emacs/wrapper.nix`: 最終的な Emacs ラッパー derivation。


* `pkgs/emacs/build/default.nix`: 個別 ELisp パッケージのビルドロジック。


* `pkgs/emacs/data/`: レジストリからパッケージメタデータを構築。


* `pkgs/emacs/lock/`: ロックファイル（`flake.lock`, `archive.lock`）の生成。


* `modules/home-manager.nix`: home-manager モジュール。



---

## 4. インストール・セットアップ

### 4.1 前提条件

* **Nix 2.9 以上**: `fetchTree` で単一ファイルを取得できる必要があるためです（Nix 2.9 未満では single-file アーカイブが除外されます）。


* **flake 機能**: 有効化されている必要があります。


* **Emacs 29+ を推奨**: Emacs 29 未満の場合、`use-package` が自動的に `extraPackages` に追加されます。



### 4.2 最小構成の `flake.nix`

以下は `twist.nix` を使う最も基本的な `flake.nix` の例です。

```nix
{
  description = "My Emacs configuration with twist.nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # --- twist.nix 本体 ---
    twist.url = "github:emacs-twist/twist.nix";

    # --- レジストリ入力（後述） ---
    melpa = {
      url = "github:melpa/melpa";
      flake = false;       # MELPA は flake ではないので明示
    };
    gnu-elpa = {
      url = "github:elpa-mirrors/elpa";
      flake = false;
    };
    nongnu = {
      url = "github:elpa-mirrors/nongnu";
      flake = false;
    };
  };

  outputs = { nixpkgs, twist, ... }@inputs:
  let
    system = "x86_64-linux";  # 自分のシステムに合わせる
    pkgs = import nixpkgs { inherit system; };

    # twist.nix の makeEnv を使って Emacs 環境を構築
    emacsEnv = twist.lib.makeEnv {
      inherit pkgs;
      emacsPackage = pkgs.emacs;          # 使用する Emacs パッケージ
      initFiles = [ ./init.el ];         # init ファイル（複数可）
      lockDir = ./lock;                   # ロックファイルを置くディレクトリ
      registries = [
        # レジストリ定義（後述）
        {
          type = "elpa";
          path = inputs.gnu-elpa.outPath + "/elpa-packages";
          core-src = pkgs.emacs.src;      # Emacs 本体ソース（コアパッケージ用）
          auto-sync-only = true;
        }
        {
          name = "melpa";                 # :pin で参照する名前
          type = "melpa";
          path = inputs.melpa.outPath + "/recipes";
        }
        {
          type = "elpa";
          path = inputs.nongnu.outPath + "/elpa-packages";
        }
      ];
    };
  in
  {
    packages.${system}.default = emacsEnv;   # nix build でビルド可能
  };
}

```

### 4.3 home-manager との統合

`twist.nix` は home-manager モジュール `emacs-twist` を提供しています。設定例は以下の通りです。

```nix
{
  outputs = { nixpkgs, home-manager, twist, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    emacsEnv = twist.lib.makeEnv { /* ... makeEnv の設定 ... */ };
  in
  {
    homeConfigurations.my-user = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        # twist.nix の home-manager モジュールを読み込む
        twist.homeModules.emacs-twist

        {
          home.username = "myuser";
          home.homeDirectory = "/home/myuser";
          home.stateVersion = "24.05";

          programs.emacs-twist = {
            enable = true;
            # makeEnv の出力を config に渡す
            config = emacsEnv;
          };
        }
      ];
    };
  };
}

```

### 4.4 初期ロックファイルの生成

初回セットアップ時にはロックファイル（`flake.lock` と `archive.lock`）が必要です。`twist.nix` はこれらを生成するための app を提供しています。

```bash
# lock ディレクトリに flake.nix と archive.lock を生成し、
# その後 nix flake lock を実行してハッシュを確定する
nix run .#lock lock/

```

この `lock` アプリは以下の処理を順に行います：

1. `lock/` ディレクトリが Git ワーキングツリー内にあることを確認します。


2. 必要なファイル（`flake.nix`, `archive.lock`）が Git インデックスに登録されていることを確認します（未登録の場合は空ファイルを `git add` します）。


3. 生成されたロックファイルを `lock/` にコピーします。


4. `lock/` ディレクトリ内で `nix flake lock` を実行します。



`update` アプリを使用すると `archive.lock` のみが更新され、`nix flake lock` は実行されません。

```bash
# アーカイブの最新版を取得して archive.lock を更新
nix run .#update lock/

```

---

## 5. flake.nix の書き方

### 5.1 テンプレートの利用

~~ `twist.nix` は基本テンプレートとして `flake.template` を提供しています（`use-package` 用）。 ~~
更新されていないため現在非推奨

```bash
# テンプレートから新しいプロジェクトを作成
nix flake init -t github:emacs-twist/twist.nix

```

### 5.2 複数システムへの対応

`flake-parts` や `flake-utils` を使用することで、複数アーキテクチャに対応させることができます。

```nix
{
  inputs = {
    systems.url = "github:nix-systems/default";
    # ... その他の inputs ...
  };

  outputs = { nixpkgs, systems, twist, ... }@inputs:
  let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in
  {
    packages = eachSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        emacs = twist.lib.makeEnv {
          inherit pkgs;
          emacsPackage = pkgs.emacs;
          initFiles = [ ./init.el ];
          lockDir = ./lock;
          registries = [ /* ... */ ];
        };
      }
    );
  };
}

```

### 5.3 init ファイルの複数指定

`initFiles` には複数のファイルを指定でき、全ファイルが連結されて 1 つの `init.el` として扱われます。

```nix
initFiles = [
  ./early-packages.el    # パッケージ定義のみ
  ./config.el            # 設定本体
  ./keybindings.el       # キーバインド
];

```

> **注意**: home-manager モジュールで `createInitFile = true` を設定した場合、`programs.emacs-twist.config`（`makeEnv` の出力）に含まれる `initFiles` が連結され、`~/.config/emacs/init.el` に配置されます。
> 
> 

### 5.4 Cachix の利用（推奨）

Emacs のビルドには時間を要するため、キャッシュサーバーを利用することを強く推奨します。

```nix
{
  nixConfig = {
    # emacs-ci キャッシュ（nix-emacs-ci 由来）
    extra-substituters = "https://emacs-ci.cachix.org";
    extra-trusted-public-keys = "emacs-ci.cachix.org-1:B5FVOrxhXXrOL0S+tQ7USrhjMT5iOPH+QN9q0NItom4=";
  };
  # ...
}

```

---

## 6. makeEnv の全オプション

`twist.lib.makeEnv` は以下の引数を取ります。これが `twist.nix` の中心的な API となります。

```nix
twist.lib.makeEnv {
  # === 必須 ===

  pkgs,                     # nixpkgs のパッケージセット
  lockDir,                  # ロックファイルディレクトリのパス
  registries,               # パッケージレジストリのリスト（後述）

  # === Emacs 本体 ===

  emacsPackage ? pkgs.emacs,  # 使用する Emacs の派生（pkgs.emacs29, emacsPgtkGcc 等）
  initFiles,                 # init ファイルのパスリスト

  # === init ファイルのパーサー ===

  initParser ? lib.parseUsePackages {},   # init ファイルを解析してパッケージ一覧を返す関数
  initReader ? file: initParser (builtins.readFile file),  # ファイルパス → パーサー結果

  # === 追加パッケージ ===

  extraPackages ? (emacs < 29 ? ["use-package"] : []),  # init ファイルに明示しない追加パッケージ名
  localPackages ? [],         # 同一リポジトリに含まれるパッケージ名（flake.lock に含めない）

  # === ビルド挙動 ===

  nativeCompileAheadDefault ? true,  # 全パッケージで事前ネイティブコンパイルを有効にするか
  wantExtraOutputs ? true,           # info 等の追加出力を生成するか
  extraOutputsToInstall ? (wantExtraOutputs ? ["info"] : []),  # インストールする追加出力

  # === ロックファイル ===

  postCommandOnGeneratingLockDir ? null,  # ロック生成後に実行するコマンド（Git リポジトリルートで実行）

  # === 組み込みライブラリ ===

  initialLibraries ? null,     # Emacs 組み込みライブラリの文字列リスト（null なら自動検出）

  # === システムパッケージ ===

  addSystemPackages ? true,    # :ensure-system-package で指定されたパッケージを PATH に追加するか

  # === パッケージオーバーライド ===

  inputOverrides ? {},         # パッケージごとのオーバーライド（後述）

  # === IFD 回避 ===

  persistMetadata ? false,     # メタデータを lock ディレクトリに永続化して IFD を回避する
  defaultMainIsAscii ? false,  # 全パッケージのメインファイルが ASCII のみと仮定する（IFD 回避）

  # === マニフェスト（実験的） ===

  exportManifest ? false,     # twist.el のホットリロード用マニフェストを出力するか

  # === その他 ===

  configurationRevision ? null,  # 設定のリビジョン文字列
  extraSiteStartElisp ? "",      # site-start.el に追加する Elisp コード
}

```

### 返り値の構造

`makeEnv` の返り値は、Elisp パッケージのスコープであり、同時に Emacs ラッパー derivation としても機能します。

```nix
env = twist.lib.makeEnv { ... };

# env 自体が Emacs ラッパー derivation として振る舞う
# nix build の結果は emacs コマンドが含まれる

env.initFiles       # init ファイルのリスト（参考用）
env.emacs           # Emacs パッケージ
env.lib             # ビルドサポートライブラリ
env.packageInputs   # パッケージメタデータの属性セット（検査用）
env.elispPackages   # 実際の ELisp パッケージ derivation のスコープ
env.builtinLibraryList  # 組み込みライブラリの一覧 derivation
env.builtinLibraries    # 組み込みライブラリ名の文字列リスト
env.maskedBuiltins      # 組み込みと同名でマスクされたパッケージ名
env.depsCheck           # 依存バージョンチェック結果
env.revDeps             # 逆依存関係のマップ
env.executablePackages  # システムパッケージのリスト
env.icons               # Emacs アイコン
env.emacsWrapper        # Emacs ラッパー derivation
env.generateLockDir     # ロックディレクトリ生成用スクリプト
env.makeApps            # lock/update アプリを生成する関数

```

---

## 7. レジストリ（registries）の種類と設定

`twist.nix` は 5 種類のレジストリ（インベントリ）に対応しています。
`registries` はリストで指定し、後の要素ほど優先度が高くなります（同じパッケージ名が複数のレジストリに存在する場合、後のものが優先されます）。

> **注意**: 旧名 `inventories` は非推奨です。`registries` を使用してください。
> 
> 

### 7.1 MELPA レシピ（type = "melpa"）

MELPA の `recipes` ディレクトリを直接参照します。各レシピファイルにはパッケージのソース取得方法が記述されています。

```nix
{
  name = "melpa";  # :pin キーワードで参照する名前（必須ではないが推奨）
  type = "melpa";
  path = inputs.melpa.outPath + "/recipes";
}

```

* **ソース取得**: レシピに基づいて GitHub 等から `fetchTree` で取得します。


* **ロック**: `flake.lock` 内にパッケージ名をキーとしてエントリが作成されます。


* **ビルド**: ソースを `doTangle = true` で展開します（org-tangle 等の処理が走る場合があります）。


* **ファイル**: MELPA レシピの `:files` ディレクティブに従ってファイルを展開します。


* **name**: 設定すると、init ファイル内で `:pin melpa` のようにピン指定が可能になります。



### 7.2 ELPA（type = "elpa"）

GNU ELPA / NonGNU ELPA の `elpa-packages` ファイルをパースします。

```nix
# GNU ELPA（コアパッケージ + 外部パッケージ）
{
  type = "elpa";
  path = inputs.gnu-elpa.outPath + "/elpa-packages";
  core-src = pkgs.emacs.src;       # Emacs 本体のソース（コアパッケージの取得に必要）
  auto-sync-only = true;           # manual-sync のパッケージを除外
}

# NonGNU ELPA
{
  type = "elpa";
  path = inputs.nongnu.outPath + "/elpa-packages";
}

```

* **コアパッケージ**: `core-src` を指定すると、Emacs リポジトリ内のファイルをソースとして使用します。


* **外部パッケージ**: `elpa-packages` に記載された URL から `fetchTree` で取得します。


* **auto-sync-only**: `true` に設定すると `manual-sync` とマークされたパッケージを除外します。


* **lisp-dir**: パッケージが `lisp-dir` 属性を持つ場合、Lisp ファイルはそのサブディレクトリから取得します。


* **make**: `:make` 属性があるパッケージはビルド時に `make` を実行します。


* **renames**: `:renames` 属性でファイルのリネームを処理します。


* **main-file**: `:main-file` 属性でメインファイルを明示的に指定します。



### 7.3 archive-contents（type = "archive-contents"）

ELPA 形式の `archive-contents` ファイルからパッケージを取得します。

```nix
{
  name = "gnu";                    # :pin で参照可能
  type = "archive-contents";
  path = inputs.gnu-elpa-archive.outPath;   # archive-contents ファイルのパス
  base-url = "https://raw.githubusercontent.com/d12frosted/elpa-mirror/master/gnu/";
}

```

* **path**: ローカルまたは URL の `archive-contents` ファイルのパスを指定します。


* **base-url**: tarball または単一ファイルのダウンロード元ベース URL を指定します。


* **対応形式**: tar（`.tar`）と single（`.el` 単一ファイル）に対応しています。


* **Nix 2.9 未満**: 単一ファイルアーカイブは除外されます（`fetchTree` の制限によるものです）。



### 7.4 アーカイブ（type = "archive"）

URL から `archive-contents` を直接読み取り、パッケージを取得します。

```nix
{
  type = "archive";
  url = "https://elpa.gnu.org/packages/archive-contents";
}

```

* archive-contents とは異なり、`path` ではなく `url` を直接指定します。


* `archive.lock` ファイルにロック情報が保存されます。



### 7.5 Git サブモジュール（type = "gitmodules"）

`.gitmodules` ファイルからパッケージを取得します。EmacsMirror の epkgs リポジトリ等で使用されます。

```nix
{
  name = "emacsmirror";
  type = "gitmodules";
  path = inputs.epkgs.outPath + "/.gitmodules";
}

```

* `.gitmodules` ファイルの各エントリをパッケージとして扱います。


* MELPA レシピと同様に `:files` ディレクティブでファイルを展開します。



### レジストリの優先順位

`registries` リストの**後方に配置された要素ほど優先**されます。同じパッケージ名が複数のレジストリに存在する場合、リストの後方にあるものが使用されます。これを利用して、特定のパッケージを特定のレジストリから取得するピン留めを実現できます。

```nix
registries = [
  # 先に定義 → 低優先度
  { type = "melpa"; name = "melpa"; path = inputs.melpa.outPath + "/recipes"; }
  # 後に定義 → 高優先度（同じパッケージ名があればこちらが優先）
  { type = "elpa"; path = inputs.gnu-elpa.outPath + "/elpa-packages"; core-src = pkgs.emacs.src; auto-sync-only = true; }
];

```

---

## 8. init ファイルのパーサー

`twist.nix` は init ファイルをパースして、必要な Elisp パッケージとシステムパッケージを自動的に検出します。パーサーは `initParser` オプションを使用してカスタマイズ可能です。

### 8.1 use-package パーサー（デフォルト）

```nix
initParser = lib.parseUsePackages { alwaysEnsure ? false }

```

`use-package` フォームをスキャンし、以下を検出します：

| 検出項目 | キーワード | 説明 |
| --- | --- | --- |
| **Elisp パッケージ** | `:ensure t` | パッケージをビルド対象に追加します。

 |
| **Elisp パッケージ（別名）** | `:ensure "package-name"` | 指定した名前のパッケージを追加します。

 |
| **パッケージピン** | `:pin registry-name` | 特定のレジストリにピン留めします。

 |
| **システムパッケージ** | `:ensure-system-package` | nixpkgs からシステムパッケージを追加します。

 |

**init.el の例**: 以下はパース対象となる `init.el` の記述例です。

```elisp
;; package.el の :ensure を無効化（twist が管理するため）
(setq use-package-ensure-function #'ignore)

(use-package magit
  :ensure t)

;; 特定レジストリから取得
(use-package ivy
  :pin gnu          ;; name = "gnu" のレジストリから取得
  :ensure t)

;; システムパッケージも同時にインストール
(use-package python
  :ensure-system-package python3
  :ensure t)

```

### 8.2 setup.el パーサー

[setup.el](https://www.google.com/search?q=https://git.sr.ht/~pkal/setup) を使用している場合のパーサー設定です。

```nix
initParser = inputs.twist.lib.parseSetup {
  inherit (inputs.nixpkgs) lib;
} {
  # setup.el の :package キーワードの代わりに使うカスタムキーワード
  # package.el の暴発を防ぐために :package を無効化した上で、
  # 独自キーワードを定義するのが推奨
  packageKeyword = ":package";
  # システムパッケージを指定するキーワード（文字列で指定、null で無効）
  nixpkgsKeyword = ":nixpkgs";
};

```

**setup.el 用のダミー `:package` 定義**:
init.el 側で package.el が意図せずパッケージを自動インストールしないように、`:package` キーワードを上書きします。

```elisp
;; package.el の自動インストールを無効化
(setup-define :package
  (lambda (package) nil)
  :shorthand 'cadr
  :repeatable t
  :documentation "Fake installation of PACKAGE.")

```

### 8.3 カスタムパーサー

独自のパーサーを定義することも可能です。パーサーは文字列を受け取り、以下の形式の属性セットを返す関数として定義します。

```nix
{
  elispPackages = [ "magit" "dash" "ivy" ];      # 文字列のリスト
  elispPackagePins = { ivy = "gnu"; };           # パッケージ名 → レジストリ名
  systemPackages = [ "git" "ripgrep" ];          # 文字列のリスト
}

```

パーサーの実装例です。

```nix
initParser = fileContent: {
  elispPackages = [ "magit" "dash" ];
  elispPackagePins = {};
  systemPackages = [];
};

```

---

## 9. home-manager モジュール

`twist.homeModules.emacs-twist` として提供される home-manager モジュールの全オプションについて解説します。

### 9.1 オプション一覧

以下はモジュールで設定可能な各オプションです。

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `enable` | bool | `false` | モジュールを有効にします。

 |
| `name` | string | `"emacs"` | ラッパースクリプトの名前を指定します。

 |
| `directory` | string | `".config/emacs"` | ホームディレクトリからの相対パスで `user-emacs-directory` を指定します。

 |
| `createInitFile` | bool | `false` | 指定ディレクトリに `init.el` を生成するか設定します。

 |
| `earlyInitFile` | null or path | `null` | `early-init.el` のソースパスを指定します。

 |
| `createManifestFile` | bool | `false` | マニフェストファイルを生成するか（ホットリロード用）設定します。

 |
| `manifestFileName` | string | `"twist-manifest.json"` | マニフェストファイル名を指定します。

 |
| `config` | attrset | — | `makeEnv` の出力を指定します（**必須**）。

 |
| `emacsclient.enable` | bool | — | emacsclient をインストールするか設定します。

 |
| `serviceIntegration.enable` | bool | `false` | systemd サービス統合を有効にします。

 |
| `icons.enable` | bool | `true` | Emacs アイコンをインストールするか設定します。

 |
| `desktopItem.desktopName` | string | `"Emacs"` | デスクトップエントリの表示名を指定します。

 |
| `desktopItem.mimeTypes` | list of string | `["text/plain" "inode/directory"]` | 関連付ける MIME タイプを指定します。

 |

### 9.2 home-manager 設定例

設定の具体例です。

```nix
programs.emacs-twist = {
  enable = true;

  # ラッパーを "my-emacs" としてインストール
  name = "my-emacs";

  # 設定ディレクトリを変更
  directory = ".local/share/emacs";

  # init ファイルと early-init ファイルを自動配置
  createInitFile = true;
  earlyInitFile = ./early-init.el;

  # ホットリロード用マニフェストを生成
  createManifestFile = true;

  # makeEnv の出力を渡す
  config = emacsEnv;

  # emacsclient もインストール
  emacsclient.enable = true;

  # systemd サービスとして Emacs を起動
  serviceIntegration.enable = true;
};

```

### 9.3 ラッパーの動作

home-manager モジュールはラッパースクリプトを作成し、以下のフラグを追加して実行します。

```bash
emacs --init-directory="$HOME/.config/emacs"

```

これにより、Nix ストア内の `init.el` ではなく、ユーザーディレクトリに配置された `init.el` が読み込まれます。Nix でビルドしたパッケージは `EMACSLOADPATH` 経由で自動的にロードされます。

---

## 10. ロックファイルの仕組み

`twist.nix` では 2 種類のロックファイルを使用します。

### 10.1 flake.lock（Git ソース用）

Git リポジトリ（MELPA レシピ・ELPA 外部パッケージ・gitmodules）のリビジョンとハッシュを記録します。フォーマットは通常の `flake.lock`（version 7）と同一です。
各パッケージは `flake.lock` の `nodes` 内に、パッケージ名をキーとしてエントリを持ちます。

### 10.2 archive.lock（アーカイブ用）

ELPA/MELPA アーカイブから取得するパッケージ（tarball / 単一ファイル）のバージョン・URL・ハッシュを記録します。JSON 形式で保存されます。

```json
{
  "project": {
    "version": "1.2.3",
    "archive": {
      "type": "tarball",
      "url": "https://example.com/project-1.2.3.tar",
      "narHash": "sha256-..."
    },
    "packageRequires": { "emacs": "29.0" },
    "inventory": {
      "url": "https://example.com/archive-contents",
      "type": "archive"
    }
  }
}

```

### 10.3 metadata.json（オプション）

`persistMetadata = true` に設定すると、パッケージのメタデータ（バージョン・依存関係・ヘッダ情報等）が `metadata.json` にキャッシュされます。これにより IFD（Import From Derivation）を回避でき、パッケージを flake の outputs に直接公開することが可能になります。

### 10.4 ロック生成コマンド

以下のコマンドを使用してロックファイルを管理します。

| コマンド | 説明 |
| --- | --- |
| `nix run .#lock DIR` | `flake.nix` と `archive.lock` を生成し、その後 `nix flake lock` を実行します。

 |
| `nix run .#update DIR` | `archive.lock` のみを最新版で更新します（`nix flake lock` はスキップされます）。

 |
| `makeEnv { ... }.generateLockDir` | ロックディレクトリを生成するスクリプトとして機能します（`postCommandOnGeneratingLockDir` に対応）。

 |

ロック生成スクリプトの CLI オプションは以下の通りです。

```
emacs-twist-write-lock [--no-update-flake-lock] [-f|--force] DIR

```

* `--no-update-flake-lock`: `nix flake update` の代わりに `nix flake lock` を実行します。


* `-f, --force`: 出力ディレクトリが既に存在している場合でも処理を強制実行します。



### 10.5 ロックディレクトリをサブフレークとして使う

`postCommandOnGeneratingLockDir` を設定することで、ロックディレクトリをメイン flake のサブフレーク入力として扱うことができます。

```nix
{
  inputs = {
    lock.url = "./lock?dir=lock";   # ロックディレクトリをサブフレークとして入力
  };

  # ...
}

```

`makeEnv` 側の設定例です。

```nix
# makeEnv 側
postCommandOnGeneratingLockDir = "nix flake lock";  # Nix 2.19+ の構文

```

---

## 11. パッケージビルドの内部動作

### 11.1 ビルドフェーズ

各 ELisp パッケージは以下のフェーズで順にビルドされます（`pkgs/emacs/build/default.nix`）。

```
unpackPhase → patchPhase → buildPhase → checkPhase → installPhase

```

> `configurePhase` はリポジトリに Makefile が含まれる場合に問題を起こす可能性があるため、意図的に除外されています。
> 
> 

### 11.2 buildPhase の詳細

ビルドフェーズでの処理内容は以下の通りです。

1. `*-pkg.el` を削除します（package.el との競合を避けるためです）。


2. バイトコンパイルを実行します（`dontByteCompile` が設定されていない場合）。


* `emacs --batch -f batch-byte-compile` が実行されます。




3. autoloads ファイルを生成します（`emacs --batch -f batch-update-autoloads`）。



### 11.3 installPhase の詳細

インストールフェーズでの処理内容は以下の通りです。

1. `site-lisp/` ディレクトリへファイルをコピーします。


* この際、`*.info`, `*.texi`, `*.texinfo`, `eln-cache` は除外されます。




2. ネイティブコンパイルを実行します（Emacs 29+ で `nativeCompileAhead = true` の場合）。


* インストール済みのファイルを対象にネイティブコンパイルが行われます。


* 生成された `.eln` ファイルは `share/emacs/native-lisp/` に配置されます。




3. info ファイルをインストールします（`wantExtraOutputs` が有効な場合）。



### 11.4 パッケージのメタデータ取得

パッケージのバージョンや依存関係、メタ情報は以下の優先順序で取得されます（`pkgs/emacs/data/package.nix`）。

1. **`metadata.json`** キャッシュ（`persistMetadata = true` かつハッシュが一致している場合）。


2. **`attrs`** で明示的に指定された値。


3. **`*-pkg.el`** ファイルの解析結果。


4. **Elisp ヘッダ**（`;; Version:`, `;; Package-Requires:` 等）の解析結果。



ヘッダのパース処理（`parseElispHeaders.nix`）では以下の情報が抽出されます。

* `Version` / `Package-Version`

* `URL` / `Homepage`

* `SPDX-License-Identifier`

* `Package-Requires`

* `Author` / `Maintainer`

* `Keywords`

* `summary`（1 行目の `---` の後のテキスト）



### 11.5 IFD（Import From Derivation）の回避

Nix における IFD は評価パフォーマンスを低下させ、flakes の constraints に違反する可能性があります。`twist.nix` では以下の手法で IFD を回避しています。

* **`defaultMainIsAscii`**: メインファイルが ASCII のみで構成されていると仮定し、`builtins.readFile` を用いて安全に読み取ります。


* **`persistMetadata`**: メタデータを `metadata.json` にキャッシュすることで、ビルド時のファイル読み取り処理自体を回避します。


* **非 ASCII ファイルのフォールバック**: `head -c 1500` コマンドを用いて最初の 1500 バイトのみを読み取ります（IFD は発生しますが影響を最小限に抑えます）。



---

## 12. パッケージのオーバーライド

### 12.1 inputOverrides

`makeEnv` の `inputOverrides` オプションを使用することで、特定パッケージの属性を個別に上書きできます。

```nix
inputOverrides = {
  # パッケージ名 → _tself: tsuper: { ... } の形式
  bbdb = _: super: {
    # ファイルを除外する例
    files = builtins.removeAttrs super.files [
      "bbdb-notmuch.el"
      "bbdb-vm.el"
      "bbdb-vm-aux.el"
    ];
  };

  # 別のミラーを使う例
  tramp = _: _: {
    origin = {
      type = "github";
      owner = "emacs-straight";
      repo = "tramp";
      ref = "master";
    };
  };
};

```

### 12.2 elispPackages スコープのオーバーライド

`elispPackages` は `makeScope` 関数で作成されたスコープであるため、`overrideScope'` を使用してビルドの挙動を変更することが可能です。

```nix
env = twist.lib.makeEnv { /* ... */ };

# 例: 特定パッケージのビルドをオーバーライド
customEnv = env.elispPackages.overrideScope' (eself: esuper: {
  auctex = esuper.auctex.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.perl pkgs.texliveSmall ];
    buildPhase = old.buildPhase + ''
      make all
    '';
  });
});

```

### 12.3 nixpkgs overlay を使ったオーバーライド

`composeExtensions` を用いることで、twist のスコープに対して nixpkgs 側で定義した overlay を適用できます。

```nix
pkgs.lib.composeExtensions
  inputs.twist-overrides.overlays.twistScope
  (import ./nix/overrides.nix { inherit pkgs; })

```

### 12.4 AUCTeX 等の複雑なパッケージのオーバーライド例

AUCTeX のように Makefile を使用するパッケージでは、ビルド時に追加の設定が必要となります。以下は実践的なオーバーライドの実装例です。

```nix
{ pkgs }:
_tself: tsuper: {
  elispPackages = tsuper.elispPackages.overrideScope (eself: esuper: {
    auctex = esuper.auctex.overrideAttrs (old: {
      outputs = [ "out" ];
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        pkgs.perl
        pkgs.texliveSmall
      ];
      # ChangeLog 生成を回避するパッチ
      postPatch = (old.postPatch or "") + ''
        sed -i '/^ChangeLog:/,/^[^[:space:]]/c\
        ChangeLog:\
        \ttouch $@\
        ' GNUmakefile
      '';
      # homeless-shelter エラーを回避
      preBuild = (old.preBuild or "") + ''
        export HOME=$PWD/.home
        export XDG_CONFIG_HOME=$HOME/.config
        export XDG_CACHE_HOME=$HOME/.cache
        export XDG_DATA_HOME=$HOME/.local/share
        mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
      '';
      # info も含めてビルド
      buildPhase = (old.buildPhase or "") + ''
        make all
      '';
      # info ファイルの手動インストール
      installPhase = (old.installPhase or "") + ''
        mkdir -p $out/share/info
        if [ -d doc ]; then
          cp doc/*.info $out/share/info/ || true
        fi
        install-info $out/share/info/auctex.info $out/share/info/dir || true
        install-info $out/share/info/preview-latex.info $out/share/info/dir || true
      '';
    });
  });
}

```

---

## 13. ラッパーの仕組み

### 13.1 ラッパーの構成

Emacs ラッパー（`pkgs/emacs/wrapper.nix`）は内部で以下の処理を行っています。

1. **パッケージ環境の構築**: `buildEnv` を用いて、全パッケージを単一の環境に統合します。


* `share/info`: info ファイルが配置されます。


* `share/emacs/native-lisp/`: ネイティブコンパイル済みのライブラリが配置されます（該当する場合）。




2. **site-start.el の生成**: autoloads を自動的にロードするための `site-start.el` を作成します。


3. **subdirs.el の生成**: `load-path` を設定するための `subdirs.el` を作成します。


4. **ラッパースクリプト**: 各種環境変数（`EMACSLOADPATH`, `INFOPATH`, `PATH` 等）を設定するスクリプトを生成します。



### 13.2 環境変数

生成されるラッパーによって、以下の環境変数が設定されます。

| 環境変数 | 設定値 | 説明 |
| --- | --- | --- |
| `EMACSLOADPATH` | `$siteLisp:` | `site-lisp` ディレクトリをロードパスの先頭に配置します。

 |
| `INFOPATH` | `emacs/info:wrapper/info:packageEnv/info` | 全ての `info` ディレクトリを連結して設定します。

 |
| `EMACSNATIVELOADPATH` | `wrapper/native-lisp:packageEnv/native-lisp:emacs/native-lisp` | ネイティブコンパイル用のロードパスを設定します（該当する場合）。

 |
| `PATH` | パッケージの `bin` ディレクトリを追加 | `:ensure-system-package` で指定されたツール群を利用可能にします。

 |

### 13.3 site-start.el の内容

生成される `site-start.el` は以下のような内容になります。

```elisp
;; load-path の設定
(setq load-path (append '("pkg1/share/emacs/site-lisp/" "pkg2/share/emacs/site-lisp/") load-path))

;; autoloads の自動ロード
(when init-file-user
  (load "pkg1/share/emacs/site-lisp/pkg1-autoloads.el" t t)
  (load "pkg2/share/emacs/site-lisp/pkg2-autoloads.el" t t)
  ;; ...
)

```

### 13.4 マニフェスト（実験的）

`exportManifest = true` を設定すると、ラッパーは JSON 形式のマニフェストを出力し、`site-start.el` に以下のコードを追加します。

```elisp
(defconst twist-running-emacs "/nix/store/.../emacs-29.4")
(defconst twist-current-manifest-file "/nix/store/.../elisp-digest.json")

```

この機能は [twist.el](https://github.com/emacs-twist/twist.el) が提供するホットリロード機能において使用されます。

---

## 14. トラブルシューティングとTips

### 14.1 よくある問題と対策

#### パッケージが見つからない

```
Error: Package xxx is not found

```

* `registries` に適切なレジストリが登録されているか確認してください。


* パッケージ名のスペルが正しいか確認してください（MELPA では小文字、ELPA では `-` 区切り等）。


* `exclude` オプションによって意図せず除外されていないか確認してください。



#### 依存バージョン不一致

`twist.nix` はビルド時に依存関係のバージョンをチェックし、不一致がある場合はエラーを出力します。

```
Warning: The following packages have insufficient dependencies:
Error: Some packages require updates: xxx yyy

```

* `nix run .#update lock/` コマンドを実行してパッケージを更新してください。


* 依存先パッケージの `inputOverrides` を利用してバージョンを調整してください。



#### ビルド時の homeless-shelter エラー

一部のパッケージはビルド中に `$HOME` ディレクトリにアクセスしようとすることがあります。

```nix
# inputOverrides で preBuild に HOME 設定を追加
preBuild = ''
  export HOME=$PWD/.home
  mkdir -p "$HOME"
'';

```

#### IFD によるパフォーマンス低下

```
warning: ignoring the user-specified option '--impure'

```

* `defaultMainIsAscii = true` オプションを試してください（ASCII のみで構成されたパッケージに有効です）。


* `persistMetadata = true` を設定し、メタデータをキャッシュしてください。



#### 改行コード問題

CRLF や CR の改行コードで保存された Elisp ファイルは、ヘッダのパースに失敗する可能性があります。ただし、`twist.nix` では既にこの問題への対策が実装されています（`parseElispHeaders.nix` において CRLF/CR を LF に正規化します）。

### 14.2 実用的な Tips

#### 組み込みライブラリとの衝突

Emacs 29+ に同梱されているパッケージ（`project`, `comint` 等）について、明示的に `:ensure t` を指定しても問題はありません。`twist.nix` が組み込みライブラリを自動的に検出し、ビルド対象から除外します。衝突してマスクされたパッケージ名は `env.maskedBuiltins` で確認可能です。

#### `:pin` で特定のレジストリに固定

```elisp
;; "gnu" という名前のレジストリから ivy を取得
(use-package ivy
  :pin gnu
  :ensure t)

```

レジストリ定義において `name` を設定していない場合は、`:pin` キーワードは使用できません。

#### ローカルパッケージの除外

同一リポジトリ内に複数のパッケージが含まれている場合、`localPackages` に指定することで、`flake.lock` への不要な差分登録を回避できます。

```nix
localPackages = [ "my-package-a" "my-package-b" ];

```

#### 逆依存の確認

`nix repl` 等を使用して、特定のパッケージに依存しているパッケージの一覧を確認できます。

```nix
env = twist.lib.makeEnv { /* ... */ };
# magit に依存するパッケージの一覧を表示
env.revDeps.magit  

```

#### デバッグ: packageInputs の検査

パッケージのメタデータは以下のようにして確認できます。

```nix
env = twist.lib.makeEnv { /* ... */ };
# パッケージのメタデータを確認
env.packageInputs.magit.src
env.packageInputs.magit.version
env.packageInputs.magit.packageRequires

```

---

## 15. 設定例

### 15.1 最小構成（パッケージなし）

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    twist.url = "github:emacs-twist/twist.nix";
  };

  outputs = { nixpkgs, twist, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    packages.${system}.default = twist.lib.makeEnv {
      inherit pkgs;
      emacsPackage = pkgs.emacs;
      initFiles = [];
      lockDir = ./lock;
      registries = [];
    };
  };
}

```

### 15.2 実用的な設定（MELPA + ELPA + home-manager）

以下は複数のレジストリと home-manager を統合した実践的な設定例です。

```nix
# flake.nix
{
  description = "My Emacs configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    twist.url = "github:emacs-twist/twist.nix";
    home-manager.url = "github:nix-community/home-manager";

    melpa = {
      url = "github:melpa/melpa";
      flake = false;
    };
    gnu-elpa = {
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

  outputs = { nixpkgs, systems, twist, home-manager, ... }@inputs:
  let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
    eachPkgs = f: eachSystem (s: f (import nixpkgs { system = s; }));

    makeEmacs = pkgs: twist.lib.makeEnv {
      inherit pkgs;
      emacsPackage = pkgs.emacs29;
      initFiles = [ ./init.el ];
      lockDir = ./lock;

      registries = [
        {
          type = "elpa";
          path = inputs.gnu-elpa.outPath + "/elpa-packages";
          core-src = pkgs.emacs29.src;
          auto-sync-only = true;
        }
        {
          name = "melpa";
          type = "melpa";
          path = inputs.melpa.outPath + "/recipes";
        }
        {
          type = "elpa";
          path = inputs.nongnu.outPath + "/elpa-packages";
        }
        {
          name = "emacsmirror";
          type = "gitmodules";
          path = inputs.epkgs.outPath + "/.gitmodules";
        }
      ];
    };
  in
  {
    packages = eachPkgs (pkgs: {
      default = makeEmacs pkgs;
    });

    apps = eachSystem (system: {
      lock = (makeEmacs (import nixpkgs { inherit system; })).makeApps {
        lockDirName = "lock";
      };
    });

    homeConfigurations = eachSystem (system:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        modules = [
          twist.homeModules.emacs-twist
          {
            home.username = "user";
            home.homeDirectory = "/home/user";
            home.stateVersion = "24.05";
            programs.emacs-twist = {
              enable = true;
              config = makeEmacs (import nixpkgs { inherit system; });
              createInitFile = true;
              emacsclient.enable = true;
            };
          }
        ];
      }
    );
  };
}

```

```elisp
;; init.el
(require 'use-package)
(setq use-package-ensure-function #'ignore)

(use-package magit
  :ensure t)

(use-package vertico
  :ensure t)

(use-package consult
  :ensure t)

(use-package orderless
  :ensure t)

(use-package which-key
  :ensure t)

;; システムパッケージの例
(use-package ripgrep
  :ensure-system-package ripgrep
  :ensure t)

```

### 15.3 setup.el を使う設定

`setup.el` をパーサーとして使用する場合の `makeEnv` の設定箇所です。

```nix
# makeEnv 呼び出し部分
twist.lib.makeEnv {
  inherit pkgs;
  emacsPackage = pkgs.emacs;
  initFiles = [ ./init.el ];
  lockDir = ./lock;
  initParser = inputs.twist.lib.parseSetup {
    inherit (inputs.nixpkgs) lib;
  } {
    packageKeyword = ":package";
    nixpkgsKeyword = ":nixpkgs";
  };
  extraPackages = [ "setup" ];  # setup.el 自体をパッケージに追加
  registries = [ /* ... */ ];
}

```

### 15.4 推奨ディレクトリ構成

プロジェクトの推奨ディレクトリ構成は以下の通りです。

```
.
├── LICENSE
├── flake.nix
├── flake.lock
├── init.el                    # メインの init ファイル
├── early-init.el              # early-init ファイル（任意）
├── lock/                      # ロックファイル用ディレクトリ（Git 管理下）
│   ├── flake.nix              # 自動生成
│   ├── flake.lock             # 自動生成
│   └── archive.lock           # 自動生成
├── nix/
│   └── overrides.nix          # パッケージオーバーライド（任意）
├── recipes/                   # カスタム MELPA レシピ（任意）
│   └── my-package
└── site-lisp/                 # ローカルの Elisp ファイル（任意）
    └── my-util.el

```

---

## 16. リファレンス: ファイル構成

`twist.nix` リポジトリを構成する主要ファイルとその役割一覧です。

```
twist.nix/
├── flake.nix                          # フレイクのエントリポイント[cite: 1]
│                                       # - lib: 公開 API (makeEnv 等)[cite: 1]
│                                       # - overlays: 非推奨の overlay API[cite: 1]
│                                       # - homeModules.emacs-twist: home-manager モジュール[cite: 1]
│                                       # - templates.default: use-package 用テンプレート[cite: 1]
│
├── lib/
│   └── default.nix                     # 公開 API の定義[cite: 1]
│                                       # - parseSetup: setup.el パーサー[cite: 1]
│                                       # - parseUsePackages: use-package パーサー[cite: 1]
│                                       # - buildElispPackage: 単一パッケージのビルド関数[cite: 1]
│                                       # - makeEnv: 環境構築のメイン API[cite: 1]
│
├── pkgs/
│   ├── default.nix                     # pkgs エントリ（makeOverridable でラップ）[cite: 1]
│   ├── overlay.nix                     # 非推奨の overlay（emacsTwist 関数）[cite: 1]
│   │
│   ├── build-support/                  # ビルドサポートライブラリ[cite: 1]
│   │   ├── default.nix                 # Elisp ヘルパーの統合、パーサーの公開[cite: 1]
│   │   ├── toNix.nix                   # 値を Nix 式に変換[cite: 1]
│   │   ├── gitUrlToAttrs.nix           # GitHub URL を flake ref attrs に変換[cite: 1]
│   │   ├── overrideAttrsByPath.nix     # ネストされた attrset のオーバーライド[cite: 1]
│   │   └── elisp/                      # Elisp 固有のパーサー群[cite: 1]
│   │       ├── parseUsePackages.nix    # use-package フォームのパーサー[cite: 1]
│   │       ├── parseSetup.nix          # setup.el フォームのパーサー[cite: 1]
│   │       ├── collectFromSetup.nix    # setup フォームからキーワード値を収集[cite: 1]
│   │       ├── parseElispHeaders.nix   # Elisp ファイルヘッダのパーサー[cite: 1]
│   │       ├── validateConfig.nix      # init パーサー出力のバリデータ[cite: 1]
│   │       ├── helpers.nix             # テスト用ヘルパー[cite: 1]
│   │       ├── readArchiveContents.nix # archive-contents のリモート読み取り[cite: 1]
│   │       ├── readArchiveContentsPath.nix # archive-contents のローカル読み取り[cite: 1]
│   │       ├── packReqEntriesToAttrs.nix   # Package-Requires のパース[cite: 1]
│   │       └── testdata/               # テスト用ヘッダファイル群[cite: 1]
│   │
│   └── emacs/                          # Emacs 関連のコアモジュール[cite: 1]
│       ├── default.nix                 # makeEnv の実装本体[cite: 1]
│       │                               # - ユーザー設定のパース[cite: 1]
│       │                               # - 依存関係の解決[cite: 1]
│       │                               # - パッケージセットの構築[cite: 1]
│       │                               # - ラッパーの生成[cite: 1]
│       │                               # - ロックファイル生成コマンド[cite: 1]
│       ├── wrapper.nix                 # Emacs ラッパー derivation[cite: 1]
│       │                               # - site-start.el と subdirs.el の生成[cite: 1]
│       │                               # - 環境変数の設定[cite: 1]
│       │                               # - autoloads の統合[cite: 1]
│       ├── build/
│       │   ├── default.nix             # 個別 ELisp パッケージのビルド[cite: 1]
│       │   │                           # - バイトコンパイル[cite: 1]
│       │   │                           # - autoloads 生成[cite: 1]
│       │   │                           # - ネイティブコンパイル（オプション）[cite: 1]
│       │   └── comp-native.el          # ネイティブコンパイル用 Elisp スクリプト[cite: 1]
│       ├── builtins.nix                # Emacs 組み込みライブラリの検出[cite: 1]
│       ├── icons.nix                   # Emacs アイコン derivation[cite: 1]
│       ├── data/
│       │   ├── default.nix             # レジストリからパッケージメタデータを構築[cite: 1]
│       │   │                           # - 依存関係の再帰的解決[cite: 1]
│       │   │                           # - inputOverrides の適用[cite: 1]
│       │   ├── package.nix             # 個別パッケージのメタデータ構築[cite: 1]
│       │   │                           # - バージョン・依存・ヘッダの統合[cite: 1]
│       │   ├── headers-to-meta.nix     # Elisp ヘッダから Nix meta attrset への変換[cite: 1]
│       │   └── inventory/              # レジストリ別のパッケージ列挙[cite: 1]
│       │       ├── default.nix         # レジストリタイプのディスパッチ[cite: 1]
│       │       ├── melpa.nix           # MELPA レシピの処理[cite: 1]
│       │       ├── elpa.nix            # ELPA (elpa-packages) の処理[cite: 1]
│       │       ├── archive.nix         # URL ベースの archive-contents の処理[cite: 1]
│       │       ├── archive-contents.nix # ローカル archive-contents の処理[cite: 1]
│       │       └── gitmodules.nix      # .gitmodules の処理[cite: 1]
│       ├── lock/
│       │   ├── default.nix             # ロックファイル生成のメインロジック[cite: 1]
│       │   │                           # - flake.nix テンプレートの生成[cite: 1]
│       │   │                           # - archive.lock の生成[cite: 1]
│       │   │                           # - metadata.json の生成[cite: 1]
│       │   ├── write-lock-1.nix        # ロック書き込みスクリプト（app 用）[cite: 1]
│       │   ├── write-lock-2.bash       # ロック書き込みスクリプト（CLI 用）[cite: 1]
│       │   └── flake-lock.nix          # 既存 flake.lock の更新ロジック[cite: 1]
│       └── tools/
│           ├── check-versions.nix      # 依存バージョンの整合性チェック[cite: 1]
│           └── reverse.nix             # 逆依存関係のマップ生成[cite: 1]
│
├── modules/
│   └── home-manager.nix                # home-manager モジュール[cite: 1]
│
├── doc/
│   ├── emacs-twist.texi                # Texinfo ドキュメント（未完成）[cite: 1]
│   ├── emacs-twist.info                # コンパイル済み info ファイル[cite: 1]
│   └── emacs-twist.org                 # Org ソース[cite: 1]
│
└── test/                               # テストスイート[cite: 1]
    ├── flake.nix                       # テスト用 flake 設定[cite: 1]
    ├── twist.nix                       # テスト用 makeEnv 設定[cite: 1]
    ├── twist-minimal.nix              # 最小テスト用設定[cite: 1]
    ├── home.nix                        # home-manager テスト用設定[cite: 1]
    ├── init.el                         # テスト用 init ファイル[cite: 1]
    ├── early-init.el                   # テスト用 early-init ファイル[cite: 1]
    ├── interactive.nix                 # インタラクティブテスト用[cite: 1]
    └── lock/                           # テスト用ロックディレクトリ[cite: 1]

```
