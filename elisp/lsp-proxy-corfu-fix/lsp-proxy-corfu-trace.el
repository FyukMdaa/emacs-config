;;; lsp-proxy-corfu-trace.el --- Tracing helpers for lsp-proxy/corfu bug -*- lexical-binding: t; -*-

;; Commentary:
;;
;; If `lsp-proxy-corfu-fix.el' alone doesn't fully resolve the bug, the
;; most likely remaining cause is that corfu's insertion itself is
;; corrupting the buffer (i.e., the bug is in the candidate string or
;; in corfu's try-completion / replace logic, NOT in the exit-function).
;;
;; This file installs tracing advices that log:
;; 1. The capf return value (bounds-start, point, candidate count).
;; 2. The buffer state at the very start of the exit-function (BEFORE
;;    any delete-region) -- this catches "buffer already broken before
;;    exit-function" cases.
;; 3. The result of corfu's `corfu--replace' (buffer before/after).
;; 4. The try-completion result returned by `lsp-proxy--dumb-tryc'
;;    (to detect the malformed `(cons LIST INTEGER)' bug).
;;
;; Enable with `M-x lsp-proxy-corfu-trace-enable', disable with
;; `M-x lsp-proxy-corfu-trace-disable'.  Read the log in the buffer
;; `*lsp-proxy-corfu-trace*'.

;;; Code:

(require 'subr-x)

(defvar lsp-proxy-corfu-trace--capf-advice nil
  "Internal: capf filter-return advice.")

(defun lsp-proxy-corfu-trace--log (fmt &rest args)
  "Log FMT with ARGS to the trace buffer."
  (let ((msg (apply #'format fmt args)))
    (with-current-buffer (get-buffer-create "*lsp-proxy-corfu-trace*")
      (goto-char (point-max))
      (insert msg "\n"))
    (message "%s" msg)))

;; 1. capf filter-return advice: log bounds-start, point, candidate count.
(defun lsp-proxy-corfu-trace--capf-filter-return (result)
  "Log capf RESULT (bounds-start, point, table, properties)."
  (when (and (consp result) (integerp (car result)))
    (let* ((beg (car result))
           (end (cadr result))
           (props (cddr result))
           (exit-fn (plist-get props :exit-function))
           (prefix (buffer-substring-no-properties beg end))
           (current (buffer-substring-no-properties
                     (max (point-min) (- (point) 10))
                     (min (point-max) (+ (point) 10)))))
      (lsp-proxy-corfu-trace--log
       "[capf] beg=%S end=%S point=%S prefix=%S exit-fn=%S around-point=%S"
       beg end (point) prefix
       (when exit-fn "<exit-fn present>")
       current)))
  result)

;; 2. Buffer snapshot at exit-function entry.
(defun lsp-proxy-corfu-trace--post-completion-around (orig candidate status)
  "Around advice for `lsp-proxy--company-post-completion'.

Calls ORIG with CANDIDATE and STATUS, but logs buffer state BEFORE
ORIG runs (i.e., right after corfu's insertion, before any
delete-region)."
  (lsp-proxy-corfu-trace--log
   "[exit-fn entry] candidate=%S status=%S point=%S"
   candidate status (point))
  (lsp-proxy-corfu-trace--log
   "  buffer BEFORE exit-fn: %S"
   (buffer-substring-no-properties (point-min) (point-max)))
  (let ((proxy-item (get-text-property 0 'lsp-proxy--item candidate)))
    (lsp-proxy-corfu-trace--log
     "  candidate text-props: lsp-proxy--item=%S resolved=%S"
     (when proxy-item "<present>")
     (when (get-text-property 0 'resolved-item candidate) "<present>")))
  (funcall orig candidate status))

;; 3. corfu--replace around-advice: log buffer before/after.
(defun lsp-proxy-corfu-trace--corfu-replace-around (orig beg end str)
  "Around advice for `corfu--replace' (BEG END STR)."
  (lsp-proxy-corfu-trace--log
   "[corfu--replace] beg=%S end=%S str=%S buffer-before=%S"
   beg end str
   (buffer-substring-no-properties
    (max (point-min) (- beg 5))
    (min (point-max) (+ end 5))))
  (funcall orig beg end str)
  (lsp-proxy-corfu-trace--log
   "  buffer-after: %S"
   (buffer-substring-no-properties
    (max (point-min) (- beg 5))
    (min (point-max) (+ (point) 10)))))

;; 4. lsp-proxy--dumb-tryc around-advice: detect malformed result.
(defun lsp-proxy-corfu-trace--dumb-tryc-around (orig pat table pred point)
  "Around advice for `lsp-proxy--dumb-tryc' (PAT TABLE PRED POINT)."
  (let ((result (funcall orig pat table pred point)))
    (lsp-proxy-corfu-trace--log
     "[dumb-tryc] pat=%S point=%S result-type=%S result=%S"
     pat point (type-of result) result)
    (when (and (consp result) (not (stringp (car result))) (not (eq (car result) t)))
      (lsp-proxy-corfu-trace--log
       "  !!! dumb-tryc returned MALFORMED result (car not string): %S"
       (car result)))
    result))

;;;###autoload
(defun lsp-proxy-corfu-trace-enable ()
  "Enable lsp-proxy + corfu completion tracing."
  (interactive)
  (require 'corfu)
  (require 'lsp-proxy-completion)
  ;; Install capf filter-return advice.
  (advice-add 'lsp-proxy-completion-at-point :filter-return
              #'lsp-proxy-corfu-trace--capf-filter-return
              '((name . lsp-proxy-corfu-trace-capf)))
  ;; Install around advices.
  (advice-add 'lsp-proxy--company-post-completion :around
              #'lsp-proxy-corfu-trace--post-completion-around
              '((name . lsp-proxy-corfu-trace-post-completion)))
  (advice-add 'corfu--replace :around
              #'lsp-proxy-corfu-trace--corfu-replace-around
              '((name . lsp-proxy-corfu-trace-corfu-replace)))
  (advice-add 'lsp-proxy--dumb-tryc :around
              #'lsp-proxy-corfu-trace--dumb-tryc-around
              '((name . lsp-proxy-corfu-trace-dumb-tryc)))
  (message "lsp-proxy-corfu-trace enabled; see buffer *lsp-proxy-corfu-trace*"))

;;;###autoload
(defun lsp-proxy-corfu-trace-disable ()
  "Disable lsp-proxy + corfu completion tracing."
  (interactive)
  (advice-remove 'lsp-proxy-completion-at-point
                  #'lsp-proxy-corfu-trace--capf-filter-return)
  (advice-remove 'lsp-proxy--company-post-completion
                  #'lsp-proxy-corfu-trace--post-completion-around)
  (advice-remove 'corfu--replace
                  #'lsp-proxy-corfu-trace--corfu-replace-around)
  (advice-remove 'lsp-proxy--dumb-tryc
                  #'lsp-proxy-corfu-trace--dumb-tryc-around)
  (message "lsp-proxy-corfu-trace disabled"))

(provide 'lsp-proxy-corfu-trace)
;;; lsp-proxy-corfu-trace.el ends here
