# lsp-proxy + corfu 補完バグ修正パッケージ

## 概要

`lsp-proxy-completion.el` と `corfu` の組み合わせで発生する、補完確定時のテキスト破壊バグに対する修正パッケージです。以下の症状を対象とします:

- Clojure / ClojureScript だけでなく、YAML / Nix / TypeScript など複数言語でも発生
- 補完位置のミス（インデントが無視される、手前の文字が消される）
- 補完文字列の重複（同じ補完文字列が2箇所に挿入される）
- 閉じ括弧や開き括弧が消える
- コード内の位置（例: `)]` のように閉じ括弧が連続する位置、YAML のネスト下）によって再現したりしなかったりする

## ファイル構成

| ファイル | 目的 |
|---|---|
| `lsp-proxy-corfu-fix.el` | バグ修正パッチ本体。`lsp-proxy--company-post-completion` と `lsp-proxy--company-post-completion-item` を `:override` advice で置き換える。 |
| `lsp-proxy-corfu-trace.el` | デバッグ用トレースパッケージ。修正後も症状が残る場合、残りの原因を切り分けるために使う。 |

## 修正の対象バグ（詳細）

### Bug 1: exit-function が corfu 挿入前の座標を現座標として使っている（主因）

`lsp-proxy--company-post-completion-item` は corfu がバッファに candidate を挿入した後に呼ばれるが、内部で使っている座標がすべて corfu 挿入前のもの:

```elisp
(start (plist-get proxy-item :start))    ; = corfu 挿入前の point
(end   (plist-get proxy-item :end))      ; = corfu 挿入前の計算座標
...
(delete-region start end)                ; post-corfu buffer で pre-corfu 座標を delete
(delete-region replaceStart replaceEnd)  ; 同上（LSP server の textEdit.range も pre-corfu）
(goto-char replaceStart)                 ; 同上
```

これにより:
- 1回目の `delete-region` が candidate の末尾以降の文字を消す（例: `)`）
- 2回目の `delete-region` が手前の文字を消す（例: `(`、インデント）
- `goto-char replaceStart; insert newText` がズレた位置に newText を挿入 → 重複発生

LSP server の `textEdit.range` が capf bounds より広い場合（YAML のインデント含む、Clojure の `(` 含むなど）に顕在化する。言語や位置に依存するのはこのため。

### Bug 2: `additionalTextEdits` のネスト構造の見落とし

```elisp
(additionalTextEdits (plist-get item :additionalTextEdits))
...
(if-let* ((resolved-item ...))
    (if-let* ((additionalTextEdits (plist-get resolved-item :additionalTextEdits)))  ; 誤り
```

`resolved-item` の構造は `(plist-get resolved-item :item)` の中に additionalTextEdits がある。これを取り逃がしているため、解決済みでも常に非同期 `completionItem/resolve` が再送される。

### Bug 3: `startPoint` を計算しているのに未使用

```elisp
(startPoint (- marker (length candidate)))  ; marker 基準の post-corfu 正しい開始位置
;; これがどこでも使われていない
```

handoff doc でも指摘済み。

### Bug 4 (Rust 側、別途): `proxy-item :start` 自体が誤り

```rust
start: context.start_point,  // = point（prefix 末尾）
end:   context.start_point + (label_len - prefix_len),
```

本来 `start` は `bounds_start`（prefix の開始）であるべき。Elisp 側の修正だけでバグは解消するが、Rust 側も別途報告すべき。

## 修正方針

eglot の標準的なアプローチを採用:

1. **corfu が capf bounds `[bounds-start, point]` に candidate（LSP `:label`）を挿入済み**という前提で始める。
2. `marker` から `cand-start = (- marker (length candidate))`, `cand-end = marker` を計算。これらは post-corfu の正しい candidate 範囲。
3. **textEdit がある場合**: まず corfu の挿入を `delete-region cand-start cand-end` で取り消す（buffer が pre-corfu 状態に戻る）。その後、server の `textEdit.range`（pre-corfu 座標）が正しく使えるようになるので、`delete-region replaceStart replaceEnd; goto-char replaceStart; insert newText` で textEdit を適用。
4. **textEdit が無い場合**: corfu が label を挿入済み。insertText が label と異なる場合のみ undo+reinsert。snippet の場合は snippet 展開。
5. 最後に `additionalTextEdits` を適用（ネスト構造を正しく読む）。

この方針は言語非依存: server の `textEdit.range` が capf bounds と一致してもしなくても、常に正しい結果になる。

## インストール手順

### 1. ファイルを load-path の通った場所に置く

ユーザーの `init.org` 設定を見ると、自作 elisp は `elisp/` 以下に置いているようなので、それに倣う:

```bash
cp lsp-proxy-corfu-fix.el    ~/emacs-twist/elisp/aozora-helper-mode/../lsp-proxy-corfu-fix.el
cp lsp-proxy-corfu-trace.el  ~/emacs-twist/elisp/lsp-proxy-corfu-trace.el
```

あるいは `load-path` の通っている任意のディレクトリで OK。

### 2. init.org に追記

`* 補完` セクションの `*** lsp-proxy` の直後に追加:

```elisp
(setup (:package lsp-proxy)
  (:nixpkgs lsp-proxy)
  (:option lsp-proxy-user-languages-config lsp-proxy-user-languages-config))

;; ↓ 追加
(setup (:package lsp-proxy-corfu-fix)
  (:require lsp-proxy-corfu-fix)
  (:with-map lsp-proxy-mode-map
    ;; lsp-proxy-mode が有効化された時に fix も有効化する
    )
  (:when-loaded
    (lsp-proxy-corfu-fix-enable)))
;; ↑ 追加
```

あるいは `setup` を使わずシンプルに:

```elisp
(with-eval-after-load 'lsp-proxy-completion
  (require 'lsp-proxy-corfu-fix)
  (lsp-proxy-corfu-fix-enable))
```

### 3. デバッグトレースを使う場合（オプション）

症状が残った場合のみ:

```elisp
(with-eval-after-load 'lsp-proxy-completion
  (require 'lsp-proxy-corfu-trace)
  (lsp-proxy-corfu-trace-enable))
```

ログは `*lsp-proxy-corfu-trace*` バッファに出力される。

## 検証ステップ（修正後）

以下のシナリオで再現しないか確認:

1. **Clojure の `)]` 位置**
   ```clojure
   (let [content ...
         ast (parse content)
         hoge (js)]   ; ← ここで "js" を補完確定
     ...)
   ```
   期待: `hoge (js->clj)` など、候補ラベルが正しく挿入される。閉じ `)` と `]` が残る。

2. **YAML のネスト下**
   ```yaml
   key:
     sub: va|    ; ← "va" を補完
   ```
   期待: インデントと `key:` 行が保持される。

3. **TypeScript / 一般的な言語**
   メソッド補完などで `additionalTextEdits`（import 追加）が正しく動くか。

4. **トレースログ確認**
   - `*lsp-proxy-corfu-trace*` で `[exit-fn entry]` の時点の buffer が既に壊れていたら、原因は corfu 挿入自体にある（追加調査が必要）。
   - `[exit-fn entry]` では壊れていなくて、`[corfu--replace]` の後の buffer が壊れていたら、corfu の `corfu--replace` 内に原因がある。
   - `[dumb-tryc]` が `!!! MALFORMED result` を出力していたら、`lsp-proxy--dumb-tryc` が `(cons LIST INTEGER)` を返している（別途報告すべき lsp-proxy 側バグ）。

## 修正が完全でなかった場合の次ステップ

もしこのパッチで症状が完全に解消しない場合、handoff doc の「exit-function 呼び出し前から buffer が壊れている」という観察が正しい可能性がある。その場合は:

1. トレースを有効化し、`*lsp-proxy-corfu-trace*` の以下の3行を確認:
   - `[capf]` 行: `beg`, `end`, `prefix` が意図通りか
   - `[corfu--replace]` 行: `str`（挿入された文字列）が候補ラベルと一致しているか、`buffer-before` と `buffer-after` を比較して corfu 挿入自体が壊れていないか
   - `[exit-fn entry]` 行: `buffer BEFORE exit-fn` が壊れているか

2. もし corfu 挿入自体が壊していたら、以下のいずれかが疑われる:
   - **corfu--base が空でない**: `corfu--compute` が `completion-boundaries` から非0の base を計算している。これは lsp-proxy の table が boundaries アクションで nil を返すのが原因だが、completion-pcm--all-completions 内部で別途境界判定が走る可能性がある。
   - **candidate 文字列が不正**: LSP `:label` に制御文字や埋め込みプロパティが含まれている。
   - **`lsp-proxy--dumb-tryc` の malformed result**: `(cons LIST INTEGER)` が返って corfu の `corfu--try-completion` がこれを `(cons STRING . INTEGER)` と解釈して壊れる。この場合、`lsp-proxy--dumb-tryc` も別途 override して `(cons pat point)` を返すよう修正すべき。

3. 上記を切り分けたら、Issue を建てる:
   - **`jadestrong/lsp-proxy`**: 上記 Bug 1/2/3 と `lsp-proxy--dumb-tryc` の malformed 戻り値
   - **`minad/corfu`**（必要なら）: corfu--replace が str を stringp で検証していない件
