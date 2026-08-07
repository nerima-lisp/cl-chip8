;;;; t/package.lisp
(defpackage #:cl-chip8/test
  (:use #:cl #:cl-chip8)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it #:expect #:signals #:run-all #:with-soft-assertions)
  ;; Test-only cl-prolog primitives. cl-chip8 imports these into its own
  ;; package already (src/package.lisp) but does not re-export them as part
  ;; of its own public API -- an application does not forward its logic
  ;; engine's primitives -- so tests that assert/retract/query facts directly
  ;; against CL-CHIP8:*RULEBASE* import them here instead. ASSERTZ and
  ;; RETRACT are plain symbols used as goal functors inside a quoted query
  ;; term (e.g. `(list 'assertz clause)` passed to QUERY-PROLOG), not
  ;; functions callable on their own -- importing them is what makes the
  ;; bare token `assertz` read as the same symbol cl-prolog's builtin
  ;; dispatch expects, per cl-prolog's own "builtin goal names" export
  ;; section.
  (:import-from #:cl-prolog
                #:query-prolog
                #:assertz
                #:retract
                #:solution-binding)
  ;; Test-only cl-tty-kit primitives: DECODE-INPUT builds real KEY-EVENTs
  ;; from a plain string for t/keypad-test.lisp (mirroring cl-nyancat's own
  ;; t/input-test.lisp), and MAKE-SCREEN/SCREEN-CELL let t/render-test.lisp
  ;; assert on painted cells without a real terminal.
  (:import-from #:cl-tty-kit
                #:decode-input
                #:make-key-event
                #:make-screen
                #:screen-cell
                #:cell-char
                #:cell-style)
  ;; Test-only cl-cli primitives for t/cli-test.lisp: PARSE-ARGV drives *APP*
  ;; through cl-cli's own parser without dispatching the handler, which would
  ;; take over the terminal (mirrors cl-nyancat's own t/package.lisp). cl-cli
  ;; is already cl-chip8's own main-system dependency (src/package.lisp), so
  ;; this needs no new test-only :depends-on entry in cl-chip8.asd -- see
  ;; cl-nyancat.asd's test system, which likewise omits "cl-cli" there.
  (:import-from #:cl-cli
                #:parse-argv
                #:run-app
                #:option-value
                #:positional-value
                #:cli-invalid-option-value)
  (:export #:run-tests))

(in-package #:cl-chip8/test)

(defun run-tests ()
  "Run every registered spec, signalling on any failure so ASDF's TEST-OP fails."
  (unless (run-all :reporter :spec)
    (error "cl-chip8 test suite failed"))
  (format t "~&cl-chip8/test: successful completion with 0 failures~%")
  t)
