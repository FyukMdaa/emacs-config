;;; lsp-proxy-corfu-fix.el --- Robust fix for lsp-proxy + corfu completion bugs -*- lexical-binding: t; -*-

;; Copyright (C) 2025
;; Author: upstream patch by Super Z
;; Keywords: tools, completion

;; This file is NOT part of GNU Emacs.

;; Commentary:
;;
;; This file replaces two functions in `lsp-proxy-completion.el' via
;; `advice-add :override' to fix the following confirmed bugs:
;;
;; 1. `lsp-proxy--company-post-completion-item' uses stale PRE-corfu
;;    coordinates (`:start'/`:end' from proxy-item and `textEdit.range'
;;    from the LSP server) as if they were POST-corfu positions when
;;    calling `delete-region' and `goto-char'.  This corrupts the buffer:
;;    - characters after the candidate get deleted (e.g. closing paren)
;;    - characters before the candidate get deleted when server's
;;      `textEdit.range' is wider than capf bounds (e.g. leading indent,
;;      opening paren in Clojure `)]', YAML `key:' prefix)
;;    - newText gets inserted at the wrong offset, producing duplicate
;;      text
;;
;; 2. The `additionalTextEdits' lookup misses the nested structure of
;;    `resolved-item' (the field is at `(plist-get (plist-get
;;    resolved-item :item) :additionalTextEdits)', not `(plist-get
;;    resolved-item :additionalTextEdits)'), causing lsp-proxy to
;;    always re-resolve via async `completionItem/resolve' even when
;;    the resolved item is already cached.
;;
;; 3. `startPoint' (the marker-based, post-corfu, correct start of the
;;    inserted candidate) is computed but never used.
;;
;; The strategy of the replacement is the one used by `eglot':
;;   - corfu has inserted the candidate string (LSP `:label') at the
;;     capf bounds `[bounds-start, point]'.
;;   - If the server provided a `textEdit', UNDO corfu's insertion first
;;     (so the buffer returns to the pre-corfu state where the server's
;;     `textEdit.range' coordinates are valid), THEN apply the textEdit.
;;   - Otherwise, if `insertText' or `label' is provided and differs
;;     from what corfu inserted, replace it.
;;   - Always apply `additionalTextEdits' (correctly read from the
;;     nested structure).
;;
;; The fix is language-agnostic: it does not matter whether the LSP
;; server's `textEdit.range' matches the capf bounds or not, since we
;; always undo+reapply when a textEdit is present.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'eglot)
(require 's)
(require 'dash)
(require 'lsp-proxy-completion)

(defcustom lsp-proxy-corfu-fix-debug nil
  "If non-nil, log debug messages to *lsp-proxy-corfu-fix-log* buffer."
  :group 'lsp-proxy
  :type 'boolean)

(defun lsp-proxy-corfu-fix--log (fmt &rest args)
  "Log a debug message FMT with ARGS to the log buffer."
  (when lsp-proxy-corfu-fix-debug
    (let ((msg (apply #'format fmt args)))
      (with-current-buffer (get-buffer-create "*lsp-proxy-corfu-fix-log*")
        (goto-char (point-max))
        (insert msg "\n"))
      (message "%s" msg))))

(defun lsp-proxy-corfu-fix--company-post-completion-item (proxy-item candidate marker)
  "Replacement for `lsp-proxy--company-post-completion-item'.

PROXY-ITEM is the proxy completion item (with :item, :start, :end, etc.).
CANDIDATE is the string corfu inserted (its length matches what was
inserted, since the candidate string IS what was inserted).
MARKER is a marker at the end of the inserted candidate (post-corfu
point), with insertion type t (it would advance on subsequent
insertions, but we will not insert after it before reading its value).

The key invariants are:
  - `cand-start'  = (- marker (length candidate)) is the POST-corfu
    start of the candidate (= bounds-start, since corfu replaced the
    prefix at bounds-start with the candidate).
  - `cand-end'    = marker is the POST-corfu end of the candidate.
  - Pre-corfu buffer state can be restored by `delete-region
    cand-start cand-end' (assuming nothing else has touched the buffer
    between corfu's insertion and our call)."
  (let* ((item (plist-get proxy-item :item))
         (label (plist-get item :label))
         (insertText (plist-get item :insertText))
         (insertTextFormat (plist-get item :insertTextFormat))
         (textEdit (plist-get item :textEdit))
         (additionalTextEdits
          ;; Try the unresolved item first, then look inside the resolved
          ;; item's nested :item plist.
          (or (plist-get item :additionalTextEdits)
              (when-let* ((resolved (get-text-property 0 'resolved-item candidate))
                           (resolved-item (plist-get resolved :item)))
                (plist-get resolved-item :additionalTextEdits))))
         (cand-len (length candidate))
         (cand-start (- marker cand-len))
         (cand-end   marker)
         (snippet-fn (and (eq insertTextFormat 2)
                          (eglot--snippet-expansion-fn))))
    (lsp-proxy-corfu-fix--log
     "post-completion-item entry: candidate=%S marker=%S cand-start=%S cand-end=%S"
     candidate marker cand-start cand-end)
    (lsp-proxy-corfu-fix--log
     "  buffer at entry: %S"
     (buffer-substring-no-properties (point-min) (point-max)))

    ;; Dispatch on what the server provided.
    (cond
     ;; Case A: server provided a textEdit.  Undo corfu's insertion,
     ;; then apply the server's textEdit.  Pre-corfu coordinates from
     ;; the server become valid again after the undo.
     (textEdit
      (let* ((range (plist-get textEdit :range))
             (replaceStart (eglot--lsp-position-to-point (plist-get range :start)))
             (replaceEnd   (eglot--lsp-position-to-point (plist-get range :end)))
             (newText (plist-get textEdit :newText))
             (cleanText (s-replace "\r" "" (or newText ""))))
        (lsp-proxy-corfu-fix--log
         "  textEdit branch: range=[%S,%S] newText=%S"
         replaceStart replaceEnd cleanText)
        ;; Undo corfu's insertion.  After this, the buffer is back to
        ;; the pre-corfu state where replaceStart/replaceEnd are valid.
        (delete-region cand-start cand-end)
        (lsp-proxy-corfu-fix--log
         "  after undo corfu insert: %S"
         (buffer-substring-no-properties (point-min) (point-max)))
        ;; Apply the server's textEdit.
        (delete-region replaceStart replaceEnd)
        (goto-char replaceStart)
        (funcall (or snippet-fn #'insert) cleanText)
        (lsp-proxy-corfu-fix--log
         "  after apply textEdit: %S"
         (buffer-substring-no-properties (point-min) (point-max)))))

     ;; Case B: no textEdit, but snippet expected.  Undo corfu's
     ;; insertion and expand insertText/label as a snippet.
     (snippet-fn
      (let ((text (or insertText label)))
        (lsp-proxy-corfu-fix--log
         "  snippet branch: text=%S (cand=%S)" text candidate)
        (delete-region cand-start cand-end)
        (funcall snippet-fn text)))

     ;; Case C: no textEdit, no snippet, but insertText provided.  If
     ;; insertText differs from what corfu inserted (the label), undo
     ;; and reinsert the correct text.
     (insertText
      (let ((text (or insertText label)))
        (lsp-proxy-corfu-fix--log
         "  insertText branch: text=%S (cand=%S)" text candidate)
        (unless (equal text candidate)
          (delete-region cand-start cand-end)
          (insert text))))

     ;; Case D: no textEdit, no snippet, no insertText.  corfu already
     ;; inserted the label; nothing to fix here.
     (t
      (lsp-proxy-corfu-fix--log
       "  no-op branch (label already inserted by corfu)")))

    ;; Apply additionalTextEdits if present.  These are typically
    ;; imports/side-effects that the server wants applied to OTHER
    ;; parts of the buffer; they are computed against the pre-corfu
    ;; document.  After our undo+reapply, the buffer is in the
    ;; post-textEdit state (the candidate has been replaced by
    ;; newText), so positions AFTER the candidate have shifted by
    ;; `(length newText) - cand-len' compared to pre-corfu.  eglot's
    ;; `eglot--apply-text-edits' uses markers anchored to the original
    ;; LSP positions, so it should handle this shift correctly when
    ;; the additionalTextEdits are at positions other than the
    ;; candidate's location.
    (when (cl-plusp (length additionalTextEdits))
      (lsp-proxy-corfu-fix--log
       "  applying additionalTextEdits: %S" additionalTextEdits)
      (eglot--apply-text-edits additionalTextEdits))

    ;; If no additionalTextEdits were available on the unresolved item,
    ;; and we don't yet have a resolved item, try async-resolve to
    ;; fetch them.  This is the lsp-proxy original behavior (which is
    ;; fine, since the async-resolve handler is independent of our
    ;; textEdit logic above).
    (when (and (not additionalTextEdits)
               (not (get-text-property 0 'resolved-item candidate))
               (plist-get proxy-item :language_server_id))
      (lsp-proxy-corfu-fix--log
       "  no additionalTextEdits locally; async-resolving")
      (-let [(callback cleanup-fn) (lsp-proxy--create-apply-text-edits-handlers)]
        (lsp-proxy--async-resolve proxy-item callback cleanup-fn)))))

(defun lsp-proxy-corfu-fix--company-post-completion (candidate status)
  "Replacement for `lsp-proxy--company-post-completion'.

CANDIDATE may have lost its text properties when corfu built the
inserted string via `(concat corfu--base candidate)'.  This wrapper
keeps the original lsp-proxy logic for TS/vtsls (which always need
resolve) and forwards to our overridden `-item' function with the
correct marker."
  (when (memq status '(finished exact))
    (let* ((proxy-item (get-text-property 0 'lsp-proxy--item candidate))
           (resolved-item (get-text-property 0 'resolved-item candidate))
           (language-server-name (plist-get proxy-item :language_server_name))
           (marker (copy-marker (point) t)))
      (lsp-proxy-corfu-fix--log
       "post-completion: candidate=%S status=%S proxy-item=%S resolved=%S marker=%S"
       candidate status
       (when proxy-item "<proxy-item present>")
       (when resolved-item "<resolved-item present>")
       marker)
      (cond
       ((null proxy-item)
        (lsp-proxy-corfu-fix--log
         "  no proxy-item on candidate (text properties lost?)"))
       ((or (equal language-server-name "typescript-language-server")
            (equal language-server-name "vtsls"))
        (if resolved-item
            (lsp-proxy-corfu-fix--company-post-completion-item
             resolved-item candidate marker)
          (let ((resolved (lsp-proxy--sync-resolve proxy-item)))
            (put-text-property 0 (length candidate) 'resolved-item resolved candidate)
            (lsp-proxy-corfu-fix--company-post-completion-item
             (or resolved proxy-item) candidate marker))))
       (t
        (lsp-proxy-corfu-fix--company-post-completion-item
         (or resolved-item proxy-item) candidate marker))))))

;;;###autoload
(defun lsp-proxy-corfu-fix-enable ()
  "Enable the lsp-proxy + corfu completion fix."
  (interactive)
  (advice-add 'lsp-proxy--company-post-completion
              :override
              #'lsp-proxy-corfu-fix--company-post-completion)
  (advice-add 'lsp-proxy--company-post-completion-item
              :override
              #'lsp-proxy-corfu-fix--company-post-completion-item)
  (message "lsp-proxy-corfu-fix enabled"))

;;;###autoload
(defun lsp-proxy-corfu-fix-disable ()
  "Disable the lsp-proxy + corfu completion fix."
  (interactive)
  (advice-remove 'lsp-proxy--company-post-completion
                  #'lsp-proxy-corfu-fix--company-post-completion)
  (advice-remove 'lsp-proxy--company-post-completion-item
                  #'lsp-proxy-corfu-fix--company-post-completion-item)
  (message "lsp-proxy-corfu-fix disabled"))

(provide 'lsp-proxy-corfu-fix)
;;; lsp-proxy-corfu-fix.el ends here
