;;; aozora-helper-mode.el --- Major mode for editing Aozora Bunko text files.

;; Copyright (C) 2010 Takashi Miyagi

;; This is free software (under the terms of the GNU GPL)

;;; Commentary:

;; これは青空文庫のテキストを入力する作業員のためのメジャーモードです。
;; 青空文庫のテキストを閲覧するだけならaozora-viewやaozora-modeをどうぞ。
;; http://lookup.cvs.sf.net/viewvc/lookup/lookup/lisp/aozora-view.el
;; http://www.ne.jp/asahi/alpha/kazu/pub/emacs/aozora.el

;;; Installation:

;; load-pathの通った場所に保存して.emacsに以下の設定を追加してください。
;;
;; (autoload 'aozora-helper-mode "aozora-helper-mode"
;;  "Major mode for editing Aozora Bunko text files." t)
;;
;; 特定のディレクトリのファイルを常にこのモードで開きたい人は
;; 以下のような行を追加してください。
;;
;; (setq auto-mode-alist
;;      (cons '("/books/.*\\.txt" . aozora-helper-mode) auto-mode-alist))

;;; Usage:

;; まず自分がよく使っている注記しか実装していません。
;;
;; C-c r ルビを挿入
;; C-c s 傍点の注記
;; C-c C-s 囲み形式の傍点注記
;; C-c b 太字の注記
;; C-c C-b 囲み形式の太字注記
;; C-c h 見出し注記(1=大, 2=中, 3=小)
;; C-c H 中見出し注記
;; C-c C-h 囲み形式の見出し注記
;; C-c C-H 囲み形式の中見出し注記
;; C-c a 注記の記号のみを追加
;; C-c C-c p ブラウザでプレビュー表示
;; C-c C-c i 字下げの注記
;; C-c C-c I インラインの字下げ注記
;; C-c C-c d 割り注の注記
;; C-c C-c h 縦中横の注記
;; C-c C-c c 底本の間違いを修正
;; C-c C-c C 底本のルビの間違いを修正
;; C-return 改ページ
;; M-return 改丁
;; M-n 次の章に移動
;; M-p 前の章に移動
;;
;; 注記についての詳細は青空文庫の注記一覧を参照してください。
;; http://www.aozora.gr.jp/annotation/
;;
;; プレビューにはtxt2xhtmlコマンドが必要です。
;; http://kumihan.aozora.gr.jp/

;;; Customization:

;; 必要であれば設定してください。
;;
;; txt2xhtmlコマンドのパスを指定
;; (setq aozora-helper-txt2xhtml-command "/path/to/t2hs.rb")
;;
;; 校閲君のチェックで対象外とする文字を指定
;; (setq aozora-helper-ignored-characters '("線" "抜" "却"))
;;
;; 小書き仮名も校閲君の対象にする
;; (add-to-list
;;  'aozora-helper-new-kanji-replace-pairs
;;  (append '(("ぁ" "あ") ("ぃ" "い") ("ぅ" "う") ("ぇ" "え") ("ぉ" "お")
;;            ("ゃ" "や") ("ゅ" "ゆ") ("ょ" "よ")
;;            ("ゃ" "や") ("ゅ" "ゆ") ("ょ" "よ") ("っ" "つ") ("ッ" "ツ"))))

;;; History:

;; 2011-04-03 Version 0.5 aozora-helper-next-chapterと
;;                        aozora-helper-prev-chapterを追加。
;; 2010-06-04 Version 0.4 チェックリストと置換リストを変数にした。
;;                        行末の空白を色付けするようにした。
;;                        aozora-helper-check-new-kanji2と
;;                        aozora-helper-list-modeを追加。
;; 2010-05-20 Version 0.3 aozora-helper-ignored-charactersを追加。
;;                        aozora-helper-correctionを追加。
;;                        aozora-helper-horizontalを追加。
;; 2010-05-02 Version 0.2 aozora-helper-check-new-kanjiを追加。
;; 2010-05-01 Version 0.1 初版

;;; Code:

(require 'cl)

(defvar aozora-helper-txt2xhtml-command "~/src/txt2xhtml/t2hs.rb"
  "txt2xhtmlコマンドのパス")

(defvar aozora-helper-ignored-characters
  "新字チェックの際に無視する文字のリスト")

(defun aozora-helper-remove-ruby ()
  "ルビを除去"
  (interactive)
  (save-excursion
    ;(replace-regexp "《[^》]*》" "")
    (while (re-search-forward "《[^》]*》" nil t)
      (replace-match "" nil nil)))
  (save-excursion
    ;(replace-string "｜" "")
    (while (search-forward "《[^》]*》" nil t)
      (replace-match "" nil t))))

(defun aozora-helper-remove-annotation ()
  "注記を除去"
  (interactive)
  (save-excursion
    ;(replace-regexp "［＃[^］]*］" "")
    (while (re-search-forward "［＃[^］]*］" nil t)
      (replace-match "" nil nil))))

(defun aozora-helper-insert-ruby ()
  "ルビを挿入"
  (interactive)
  (insert "《》")
  (backward-char 1))

(defun aozora-helper-insert-annotation-common ()
  "注記の記号のみを追加"
  (interactive)
  (insert "［＃］")
  (backward-char 1))

(defun aozora-helper-annotate-region (label-suffix
                                      &optional label-prefix point)
  "注記を追加"
  (let ((begin (mark))
        (end (point)))
    (unless (eq end (max begin end))
      (let ((tmp begin))
        (setq begin end
              end tmp)))
    (goto-char end)
    (if point (forward-char point))
    (if label-prefix (insert (concat "［＃" label-prefix "「"))
      (insert "［＃「"))
    (insert (replace-regexp-in-string "《[^》]*》\\｜" "" ; ルビは削除
                                      (buffer-substring begin end)))
    (insert (concat "」" label-suffix "］"))))

(defun aozora-helper-annotate-enclosed (label)
  "囲み形式の注記"
    (let ((begin (mark))
          (end (point))
          (string (concat "［＃" label "］")))
      (unless (eq end (max begin end))
        (let ((tmp begin))
          (setq begin end
                end tmp)))
      (goto-char begin)
      (insert string)
      (goto-char (+ end (length string)))
      (insert (concat "［＃" label "終わり］"))))

(defun aozora-helper-heading (size &optional enclosed)
  "見出し注記"
  (interactive "nSize (1-3; 1 biggest): ")
  (let ((label))
    (cond ((eq size 1) (setq label "大"))
          ((eq size 2) (setq label "中"))
          ((eq size 3) (setq label "小")))
    (if (eq enclosed t)
        (aozora-helper-annotate-enclosed (concat label "見出し"))
      (aozora-helper-annotate-region (concat "は" label "見出し")))))

(defun aozora-helper-heading-enclosed (size)
  "囲み形式の見出し注記"
  (interactive "nSize (1-3; 1 biggest): ")
  (aozora-helper-heading size t))

(defun aozora-helper-heading-1 ()
  "大見出し注記"
  (interactive)
  (aozora-helper-heading 1))

(defun aozora-helper-heading-enclosed-1 ()
  "囲み形式の大見出し注記"
  (interactive)
  (aozora-helper-heading 1 t))

(defun aozora-helper-heading-2 ()
  "中見出し注記"
  (interactive)
  (aozora-helper-heading 2))

(defun aozora-helper-heading-enclosed-2 ()
  "囲み形式の中見出し注記"
  (interactive)
  (aozora-helper-heading 2 t))

(defun aozora-helper-heading-3 ()
  "小見出し注記"
  (interactive)
  (aozora-helper-heading 3))

(defun aozora-helper-heading-enclosed-3 ()
  "囲み形式の小見出し注記"
  (interactive)
  (aozora-helper-heading 3 t))

;; TODO: C-u付きで他の記号の傍点を指定できるようにする。
;; http://www.aozora.gr.jp/annotation/emphasis.html#boten_chuki
;; 「白ゴマ傍点」「丸傍点(●)」「白丸傍点(○)」「黒三角傍点(▲)」
;; 「白三角傍点(△)」「二重丸傍点(◎)」「蛇の目傍点」
(defun aozora-helper-sesame-dot ()
  "傍点の注記"
  (interactive)
  (aozora-helper-annotate-region "に傍点"))

(defun aozora-helper-sesame-dot-enclosed ()
  "囲み形式の傍点注記"
  (interactive)
  (aozora-helper-annotate-enclosed "傍点"))

(defun aozora-helper-bold ()
  "太字の注記"
  (interactive)
  (aozora-helper-annotate-region "は太字"))

(defun aozora-helper-bold-enclosed ()
  "囲み形式の太字注記"
  (interactive)
  (aozora-helper-annotate-enclosed "太字"))

(defun aozora-helper-indent-block (size)
  "字下げの注記"
  (interactive "sSize: ")
  (insert (concat "［＃ここから" (japanese-zenkaku size) "字下げ］\n"))
  (insert "［＃ここで字下げ終わり］"))

(defun aozora-helper-indent-inline (size)
  "インラインの字下げ注記"
  (interactive "sSize: ")
  (insert (concat "［＃" (japanese-zenkaku size) "字下げ］")))

(defun aozora-helper-double-lines ()
  "割り注の注記"
  (interactive)
  (aozora-helper-annotate-enclosed "割り注"))

(defun aozora-helper-correction ()
  "底本の間違いを修正"
  (interactive)
  (aozora-helper-annotate-region "は底本では「」")
  (backward-char 2))

(defun aozora-helper-correction-ruby ()
  "底本のルビの間違いを修正"
  (interactive)
  (aozora-helper-annotate-region "は底本では「」" "ルビの" 1)
  (backward-char 2))

(defun aozora-helper-horizontal ()
  "縦中横の注記"
  (interactive)
  (aozora-helper-annotate-region "は縦中横"))

(defun aozora-helper-horizontal-block ()
  "横組みの注記"
  (interactive)
  (insert "［＃ここから横組み］\n")
  (insert "［＃ここで横組み終わり］"))

(defun aozora-helper-insert-new-page ()
  "改ページの注記を追加"
  (interactive)
  (insert "［＃改ページ］\n"))

(defun aozora-helper-insert-new-page-odd ()
  "改丁の注記を追加"
  (interactive)
  (insert "［＃改丁］\n"))

(defun aozora-helper-next-chapter ()
  "次の章に移動"
  (interactive)
  (search-forward "見出し］"))

(defun aozora-helper-prev-chapter ()
  "前の章に移動"
  (interactive)
  (search-backward "見出し］"))

(defvar aozora-helper-new-buffer-template
  (concat
   "作品名\n"
   "著者名\n"
   "\n"
   "-------------------------------------------------------\n"
   "【テキスト中に現れる記号について】\n"
   "\n"
   "《》：ルビ\n"
   "（例）\n"
   "\n"
   "｜：ルビの付く文字列の始まりを特定する記号\n"
   "（例）\n"
   "\n"
   "［＃］：入力者注　主に外字の説明や、傍点の位置の指定\n"
   "　　（数字は、JIS X 0213の面区点番号、または底本のページと行数）\n"
   "（例）\n"
   "-------------------------------------------------------\n"
   "\n"
   "\n"
   "\n"
   "底本：\n"
   "初出：\n"
   "※底本は、物を数える際や地名などに用いる「ヶ」（区点番号5-86）を、"
   "大振りにつくっています。\n"
   "入力：\n"
   "校正：\n"
   "YYYY年MM月DD日作成\n"
   "青空文庫作成ファイル：\n"
   "このファイルは、インターネットの図書館、"
   "青空文庫（http://www.aozora.gr.jp/）で作られました。"
   "入力、校正、制作にあたったのは、ボランティアの皆さんです。\n")
  "新規作成テンプレート")

(defun aozora-helper-insert-template ()
  "テンプレートを挿入"
  (interactive)
  (insert aozora-helper-new-buffer-template))

(defvar aozora-helper-jisx0213-characters
  ;; http://www.aozora.gr.jp/newJIS-Kanji/gokan_henkou_list.html
  '(
    ;; 78互換包摂 29字
    "噌" "爰" "頴" "鸛" "叱" "躯" "麹" "籔" "屓" "繍"
    "蒋" "醢" "蝋" "攘" "簞" "撹" "填" "頓" "祷" "祯"
    "潸" "壙" "溂" "醊" "駲" "籔" "撹" "填" "頓" "祷"
    "祯" "潸" "壙" "溂" "醊" "駲" "籐" "蔦" "攸" "歛"
    ;; 包摂規準の適用が除外 104字
    "侮" "併" "僧" "免" "勉" "勤" "卑" "即" "喝" "嘆"
    "器" "塀" "塁" "墻" "墨" "寧" "層" "巣" "廣" "徳"
    "徳" "悔" "慨" "憎" "懲" "戻" "掲" "撃" "敏" "既"
    "晩" "暑" "暦" "曙" "欺" "概" "横" "欄" "歩" "歴"
    "殺" "毎" "海" "浅" "涙" "渓" "渉" "温" "漢" "瀬"
    "煮" "状" "猪" "琢" "瓶" "研" "碑" "社" "祷" "祈"
    "祷" "祖" "祝" "神" "祥" "福" "禎" "福" "穂" "突"
    "節" "緑" "糸" "緣" "練" "繁" "署" "者" "臭" "著"
    "薫" "虚" "虚" "褸" "視" "諸" "謙" "謹" "賓" "頼"
    "賛" "逸" "郎" "都" "郷" "録" "錬" "隆" "難" "響"
    "頻" "類" "黄" "黒"
    )
  "新JIS漢字で扱いが変わる文字のリスト")

(defun aozora-helper-check-jisx0213-characters ()
  "新JIS漢字で扱いが変わる文字をチェック"
  (interactive)
  (occur (mapconcat 'identity aozora-helper-jisx0213-characters "\\|")))

(defvar aozora-helper-new-kanji-replace-pairs
  '(
    ;; 置換リストは校閲君 1.2.1aから流用
    ;; http://www.aozora.jp/kouetsukun/replace.cgi

    ;; 新字体・旧字体
    ("亜" "亞") ("悪" "惡") ("圧" "壓") ("囲" "圍") ("為" "爲")
    ("医" "醫") ("壱" "壹") ("稲" "稻") ("飲" "飮") ("陰" "陰")
    ("営" "營") ("栄" "榮") ("衛" "衞") ("駆" "驅") ("円" "圓")
    ("艶" "艷") ("塩" "鹽") ("奥" "奧") ("応" "應") ("欧" "歐")
    ("殴" "毆") ("穏" "穩") ("仮" "假") ("価" "價") ("画" "畫")
    ("会" "會") ("壊" "壞") ("懐" "懷") ("絵" "繪") ("拡" "擴")
    ("殻" "殼") ("覚" "覺") ("学" "學") ("岳" "嶽") ("楽" "樂")
    ("勧" "勸") ("巻" "卷") ("歓" "歡") ("缶" "罐") ("観" "觀")
    ("関" "關") ("陥" "陷") ("岐" "岐") ("顔" "顏") ("帰" "歸")
    ("気" "氣") ("亀" "龜") ("偽" "僞") ("戯" "戲") ("犠" "犧")
    ("旧" "舊") ("拠" "據") ("挙" "擧") ("峡" "峽") ("挟" "挾")
    ("狭" "狹") ("暁" "曉") ("区" "區") ("駆" "驅") ("勲" "勳")
    ("径" "徑") ("恵" "惠") ("渓" "溪") ("経" "經") ("継" "繼")
    ("蛍" "螢") ("営" "營") ("軽" "輕") ("鶏" "鷄") ("芸" "藝")
    ("欠" "缺") ("倹" "儉") ("剣" "劍") ("圏" "圈") ("検" "檢")
    ("権" "權") ("献" "獻") ("県" "縣") ("険" "險") ("顕" "顯")
    ("験" "驗") ("厳" "嚴") ("効" "效") ("広" "廣") ("恒" "恒")
    ("皇" "皇") ("号" "號") ("国" "國") ("済" "濟") ("砕" "碎")
    ("斎" "齊") ("剤" "劑") ("桜" "櫻") ("冊" "冊") ("雑" "雜")
    ("参" "參") ("惨" "慘") ("棧" "棧") ("蚕" "蠶") ("賛" "讚")
    ("残" "殘") ("糸" "絲") ("歯" "齒") ("児" "兒") ("辞" "辭")
    ("湿" "濕") ("実" "實") ("舎" "舎") ("写" "寫") ("釈" "釋")
    ("寿" "壽") ("収" "收") ("従" "從") ("渋" "澁") ("獣" "獸")
    ("縦" "縱") ("縦" "縱") ("処" "處") ("叙" "敘") ("奨" "奬")
    ("将" "將") ("焼" "燒") ("称" "稱") ("証" "證") ("乗" "乘")
    ("剰" "剩") ("壌" "壤") ("嬢" "孃") ("条" "條") ("浄" "淨")
    ("畳" "疊") ("穣" "穣") ("譲" "讓") ("醸" "釀") ("嘱" "囑")
    ("触" "觸") ("寝" "寢") ("慎" "慎") ("晋" "晋") ("真" "真")
    ("尽" "盡") ("図" "圖") ("粋" "粹") ("醉" "醉") ("随" "隨")
    ("髄" "髄") ("数" "數") ("枢" "樞") ("声" "聲") ("静" "靜")
    ("斉" "齊") ("摂" "攝") ("窃" "竊") ("専" "專") ("戦" "戰")
    ("浅" "淺") ("潜" "潜") ("繊" "纖") ("践" "踐") ("銭" "錢")
    ("禅" "禪") ("双" "雙") ("壮" "壯") ("捜" "搜") ("争" "爭")
    ("総" "總") ("聡" "聰") ("荘" "莊") ("装" "裝")
    ("騒" "騷") ("蔵" "藏") ("属" "屬") ("続" "續")
    ("堕" "墮") ("体" "體") ("対" "對") ("帯" "帶") ("滞" "滯")
    ("台" "臺") ("滝" "瀧") ("択" "擇") ("沢" "澤") ("単" "單")
    ("担" "擔") ("胆" "膽") ("団" "團") ("弾" "彈") ("断" "斷")
    ("痴" "癡") ("遅" "遲") ("昼" "晝") ("虫" "蟲") ("鋳" "鑄")
    ("庁" "廳") ("聴" "聽") ("鎮" "鎭") ("逓" "遞") ("鉄" "鐵")
    ("転" "轉") ("点" "點") ("伝" "傳") ("党" "黨") ("痘" "痘")
    ("灯" "燈") ("当" "當") ("闘" "鬥") ("独" "獨") ("読" "讀")
    ("届" "屆") ("県" "縣") ("弁" "辮") ("悩" "惱") ("脳" "腦")
    ("廃" "廢") ("拝" "拜") ("売" "賣") ("麦" "麥") ("発" "發")
    ("髪" "髮") ("抜" "拔") ("蛮" "蠻") ("秘" "祕") ("浜" "濱")
    ("払" "拂") ("仏" "佛") ("並" "竝") ("変" "變") ("辺" "邊")
    ("弁" "辨") ("舎" "舎") ("穂" "穗") ("豊" "豐")
    ("没" "沒") ("万" "萬") ("満" "滿") ("黙" "默") ("弥" "彌")
    ("薬" "藥") ("訳" "譯") ("予" "豫") ("余" "餘") ("与" "與")
    ("誉" "譽") ("揺" "搖") ("様" "樣") ("謡" "謠") ("来" "來")
    ("乱" "亂") ("覧" "覽") ("竜" "龍") ("両" "兩") ("猎" "猟")
    ("壌" "壤") ("励" "勵") ("礼" "禮") ("霊" "靈") ("齢" "齡")
    ("恋" "戀") ("炉" "爐") ("労" "勞") ("楼" "樓") ("禄" "祿")
    ("湾" "灣") ("湾" "灣") ("勅" "勅") ("覇" "霸") ("翻" "翻")
    ("毎" "毎") ("遙" "遙") ("予" "予") ("瑶" "瑤")

    ;; 異体字
    ("芦" "蘆") ("鯵" "鯵") ("欝" "鬱") ("廃" "廢") ("曽" "曾")
    ("烟" "煙") ("鴎" "鷗") ("蝋" "蠟") ("鎌" "鎌") ("撹" "擾")
    ("竃" "竈") ("潅" "灌") ("諌" "諌") ("却" "却") ("憑" "憑")
    ("携" "携") ("飴" "飴") ("礒" "磯") ("糜" "糜") ("諚" "謚")
    ("刃" "刃") ("靭" "靭") ("翌" "翌") ("線" "線") ("賭" "賭")
    ("曾" "曾") ("稚" "穉") ("壙" "壙") ("紘" "紘") ("涛" "濤")
    ("妊" "妊") ("禎" "禎") ("蝿" "蝿") ("凩" "凩") ("椅" "椅")
    ("萌" "萌") ("褒" "褒") ("冒" "冒") ("儘" "儘") ("澪" "澪")
    ("篭" "籠") ("仮" "仮") ("僧" "僧") ("懐" "懐") ("抬" "抬")
    ("昃" "昃") ("枡" "桝") ("横" "横") ("殻" "殻") ("玻" "玻")
    ("畸" "畸") ("箏" "箏") ("箒" "箒") ("縒" "縒") ("美" "美")
    ("膩" "膩") ("蝨" "蝨") ("譖" "譖") ("逹" "逹") ("鈔" "鈔")
    ("鈸" "鈸") ("鵞" "鵞") ("穏" "穏") ("穂" "穂") ("箆" "箆")
    ("往" "往") ("噸" "噸") ("券" "券") ("竪" "竪") ("厨" "厨")
    ("藪" "藪") ("陰" "陰") ("付" "附")
    ("連" "聯") ("罰" "罰") ("隷" "隷") ("紅" "紅") ("回" "回")
    ("廻" "※［＃「廻」つくりの縦棒が下に突き抜けている、第4水準2-12-11］")
    ("挿" "插※［＃「插」でつくりの縦棒が下に突き抜けている、第4水準2-13-28］")
    )
  "新字チェックの置換リスト")

(defun aozora-helper-check-new-kanji (begin end)
  "旧字ファイルに紛れ込んだ新字をチェック

`aozora-helper-check-new-kanji2'の方がおすすめ。"
  (interactive "r")
  ;; http://www.aozora.gr.jp/tools/kouetsukun/online_kouetsukun.html
  (let ((cur-buffer (current-buffer))
        (tmp-buffer (get-buffer-create "*aozora-helper-temp-buffer*")))
    (set-buffer tmp-buffer)
    (erase-buffer)
    (insert-buffer-substring cur-buffer begin end)
    (mapc
     (lambda (arg)
       (unless (member (car arg) aozora-helper-ignored-characters)
         (goto-char (point-min))
         (while (search-forward (car arg) nil t)
           (let ((pos (point)))
             (replace-match (concat "▼" (car arg) (cadr arg) "▲"))
             (put-text-property pos (1- (point))
                                'face 'aozora-helper-warning-face)))))
     aozora-helper-new-kanji-replace-pairs)
    ;(display-buffer tmp-buffer)
    (pop-to-buffer tmp-buffer)))

(defun aozora-helper-check-new-kanji2 (begin end)
  "旧字ファイルに紛れ込んだ新字をチェック(文字だけ抜き出して表示)

通常の校閲君方式ではチェックすべき文字が見つけにくいので
もう少し探しやすいように表示する。

チェック結果の画面で改行やSPCを入力すると対応する本文に飛ぶ。
TABやC-c C-cを押すと対応する本文を表示するけどカーソルはそのまま。
詳しくは`aozora-helper-list-mode'をどうぞ。"
  (interactive "r")
  (save-excursion
    (let ((cur-buffer (current-buffer))
          (tmp-buffer (get-buffer-create "*aozora-helper-temp-buffer*"))
          (string)
          (matched-list))
      (goto-char begin)
      (mapc
       (lambda (arg)
         (unless (member (car arg) aozora-helper-ignored-characters)
           (goto-char begin)
           (while (search-forward (car arg) end t)
             (setq string (concat "▼" (car arg) (cadr arg) "▲"))
             (push (cons (1- (point)) string) matched-list))))
       aozora-helper-new-kanji-replace-pairs)

      (if matched-list
          (progn
            (message "%d matches" (length matched-list))
            (set-buffer tmp-buffer)
            (erase-buffer)
            (dolist (item matched-list)
              (let ((pos (point)))
                (insert (format "%d:%s\n" (car item) (cdr item)))
                (put-text-property pos (point)
                                   'aozora-helper-position (car item))
                (put-text-property pos (point)
                                   'aozora-helper-buffer cur-buffer)))
            (sort-numeric-fields 1 (point-min) (point-max))
            (goto-char (point-min))
            (aozora-helper-list-mode)
            ;(display-buffer tmp-buffer)
            (pop-to-buffer tmp-buffer))
        (message "No matches")))))

(defun aozora-helper-list-jump (&optional other-window)
  "チェック結果に対応する本文に飛ぶ"
  (interactive)
  (let ((buffer (get-text-property (point) 'aozora-helper-buffer))
        (pos (get-text-property (point) 'aozora-helper-position)))
    (when (and buffer pos)
      (pop-to-buffer buffer)
      (goto-char pos)
      (when other-window
        (other-window 1)))))

(defun aozora-helper-list-display ()
  "チェック結果に対応する本文を表示するけどバッファは移動しない"
  (interactive)
  (aozora-helper-list-jump t))

(defvar aozora-helper-list-mode-map () "Keymap for aozora-helper-list-mode")
(unless aozora-helper-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "n" 'next-line)
    (define-key map "p" 'previous-line)
    ;(define-key map "q" 'bury-buffer)
    (define-key map "q" 'delete-window)
    (define-key map "\r" 'aozora-helper-list-jump)
    (define-key map " " 'aozora-helper-list-jump)
    (define-key map "\C-c\C-c" 'aozora-helper-list-jump)
    (define-key map "\C-o" 'aozora-helper-list-display)
    (define-key map "\t" 'aozora-helper-list-display)
    (setq aozora-helper-list-mode-map map)))

(defun aozora-helper-list-mode ()
  "新字チェックの結果などを表示して本文にジャンプするためのモード

\\{aozora-helper-list-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (use-local-map aozora-helper-list-mode-map)
  (setq major-mode 'aozora-helper-list-mode)
  (setq mode-name "Aozora helpr list")
  (run-hooks 'aozora-helper-list-mode-hook))

;; 色付け
(defgroup aozora-helper-faces nil
  "Faces used in Aozora helper mode"
  :group 'aozora-helper
  :group 'faces)
(defface aozora-helper-template-face
  '((t :inherit font-lock-doc-face)) nil :group 'aozora-helper)
(defface aozora-helper-ruby-face
  '((t :inherit font-lock-comment-face)) nil :group 'aozora-helper)
(defface aozora-helper-ruby-delimiter-face
  '((t :inherit font-lock-comment-delimiter-face)) nil :group 'aozora-helper)
(defface aozora-helper-annotation-face
  '((t :inherit font-lock-function-name-face)) nil :group 'aozora-helper)
(defface aozora-helper-whitespace-face
  '((t :background "red")) nil :group 'aozora-helper)
(defface aozora-helper-warning-face
  '((t :background "yellow")) nil :group 'aozora-helper)
(defvar aozora-helper-template-face 'aozora-helper-template-face)
(defvar aozora-helper-ruby-face 'aozora-helper-ruby-face)
(defvar aozora-helper-ruby-delimiter-face 'aozora-helper-ruby-delimiter-face)
(defvar aozora-helper-annotation-face 'aozora-helper-annotation-face)
(defvar aozora-helper-whitespace-face 'aozora-helper-whitespace-face)
(defvar aozora-helper-keywords-template
  (list
   (cons
    (concat
     "^-------------------------------------------------------$\\|"
     "^【テキスト中に現れる記号について】$\\|"
     "^《》：ルビ$\\|"
     "^｜：ルビの付く文字列の始まりを特定する記号$\\|"
     "^［＃］：入力者注　主に外字の説明や、傍点の位置の指定$\\|"
     "^　　（数字は、JIS X 0213の面区点番号、または底本のページと行数）$\\|"
     "^底本：\\|"
     "^底本の親本：\\|"
     "^初出：\\|"
     "^※底本は、物を数える際や地名などに用いる「ヶ」（区点番号5-86）を、"
     "大振りにつくっています。\\|"
     "^入力：\\|"
     "^校正：\\|"
     "^YYYY年MM月DD日作成$\\|"
     "^青空文庫作成ファイル：$\\|"
     "^このファイルは、インターネットの図書館、"
     "青空文庫（http://www.aozora.gr.jp/）で作られました。"
     "入力、校正、制作にあたったのは、ボランティアの皆さんです。$")
    'aozora-helper-template-face)))
(defvar aozora-helper-mode-font-lock-keywords
  (append
   aozora-helper-keywords-template
   '(("［＃[^］]*］" . aozora-helper-annotation-face)
     ("《[^》]*》" . aozora-helper-ruby-face)
     ("｜" . aozora-helper-ruby-delimiter-face)
     (" \\|\t\\|　$" . aozora-helper-whitespace-face))))

(defun aozora-helper-txt2xhtml ()
  "txt2xhtmlを実行"
  (let ((src-file (make-temp-file "aozora-helper-src"))
        (html-file (make-temp-file "aozora-helper-html"))
        (coding-system-for-read 'sjis-dos)
        (coding-system-for-write 'sjis-dos))
    (write-region (point-min) (point-max) src-file)
    (shell-command
     (concat
      aozora-helper-txt2xhtml-command " " src-file " " html-file))
    (save-excursion
      (get-buffer-create "*aozora-helper-output*")
      (set-buffer "*aozora-helper-output*")
      (erase-buffer)
      (insert-file-contents html-file)
      (delete-file src-file)
      (delete-file html-file))))

(defun aozora-helper-preview ()
  "txt2xhtmlの結果をブラウザでプレビュー"
  (interactive)
  (aozora-helper-txt2xhtml)
  (browse-url-of-buffer "*aozora-helper-output*"))

;; キーマップの定義
(defvar aozora-helper-mode-map () "Keymap for aozora-helper-mode")
(unless aozora-helper-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-cr" 'aozora-helper-insert-ruby)
    (define-key map "\C-cs" 'aozora-helper-sesame-dot)
    (define-key map "\C-c\C-s" 'aozora-helper-sesame-dot-enclosed)
    (define-key map "\C-cb" 'aozora-helper-bold)
    (define-key map "\C-c\C-b" 'aozora-helper-bold-enclosed)
    (define-key map "\C-ch" 'aozora-helper-heading)
    (define-key map "\C-cH" 'aozora-helper-heading-2)
    (define-key map "\C-c\C-h" 'aozora-helper-heading-enclosed)
    (define-key map "\C-c\C-H" 'aozora-helper-heading-enclosed-2)
    (define-key map "\C-ca" 'aozora-helper-insert-annotation-common)
    (define-key map "\C-c\C-cp" 'aozora-helper-preview)
    (define-key map "\C-c\C-ci" 'aozora-helper-indent-block)
    (define-key map "\C-c\C-cI" 'aozora-helper-indent-inline)
    (define-key map "\C-c\C-cd" 'aozora-helper-double-lines)
    (define-key map "\C-c\C-ch" 'aozora-helper-horizontal)
    (define-key map "\C-c\C-cc" 'aozora-helper-correction)
    (define-key map "\C-c\C-cC" 'aozora-helper-correction-ruby)
    (define-key map [C-return] 'aozora-helper-insert-new-page)
    (define-key map [M-return] 'aozora-helper-insert-new-page-odd)
    (define-key map "\M-n" 'aozora-helper-next-chapter)
    (define-key map "\M-p" 'aozora-helper-prev-chapter)
    (setq aozora-helper-mode-map map)))

;; メジャーモードの定義
(define-derived-mode aozora-helper-mode text-mode
  "Aozora helper"
  "Major mode for editing Aozora Bunko text files."
  (set (make-local-variable 'font-lock-defaults)
       '(aozora-helper-mode-font-lock-keywords)))

(provide 'aozora-helper-mode)

;;; aozora-helper-mode.el ends here
