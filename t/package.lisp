;;;; t/package.lisp
(defpackage #:cl-chip8/test
  (:use #:cl #:cl-chip8)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.
  (:shadowing-import-from #:cl-weave #:describe)
  ;; BEFORE-EACH is cl-weave's Vitest-style suite hook: it registers a form to
  ;; run before every IT directly inside its enclosing DESCRIBE (and any
  ;; nested DESCRIBE), so a family of tests that all start from the same
  ;; machine-reset call states that once, in the DESCRIBE body, instead of
  ;; repeating it at the top of every IT.
  (:import-from #:cl-weave
                #:it #:expect #:signals #:run-all #:with-soft-assertions #:before-each)
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

(defun run-tests (&key coverage coverage-output coverage-report-directory coverage-include-pathnames coverage-exclude-pathnames coverage-minimum-expression coverage-minimum-branch) "Run every registered spec and signal on failure so ASDF TEST-OP fails." (unless (run-all :reporter :spec :pass-with-no-tests nil :coverage coverage :coverage-output coverage-output :coverage-report-directory coverage-report-directory :coverage-include-pathnames coverage-include-pathnames :coverage-exclude-pathnames coverage-exclude-pathnames :coverage-minimum-expression coverage-minimum-expression :coverage-minimum-branch coverage-minimum-branch :coverage-reset t) (error "cl-chip8 test suite failed")) (format t "~&cl-chip8/test: successful completion with 0 failures~%") t)
