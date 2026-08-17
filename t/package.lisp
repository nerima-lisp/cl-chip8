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
  ;; SKIP is cl-weave's run-time skip: it invokes the SKIP-TEST restart that
  ;; CALL-TEST-ATTEMPT/RESTARTS establishes around the whole test body, so a
  ;; test can decide to skip after reading the environment and carry a reason
  ;; string with it. IT-SKIP / IT-SKIP-IF decide at registration time instead,
  ;; which is too early for t/corpus-test.lisp's CL_CHIP8_ROM_CORPUS check.
  ;; A skip is reported and counted, so an absent corpus shortens nothing
  ;; silently.
  (:import-from #:cl-weave
                #:it #:expect #:signals #:run-all #:with-soft-assertions #:before-each
                #:skip)
  ;; Test-only cl-prolog-kit primitives. cl-chip8 imports these into its own
  ;; package already (src/package.lisp) but does not re-export them as part
  ;; of its own public API -- an application does not forward its logic
  ;; engine's primitives -- so tests that assert/retract/query facts directly
  ;; against CL-CHIP8:*RULEBASE* import them here instead. ASSERTZ and
  ;; RETRACT are plain symbols used as goal functors inside a quoted query
  ;; term (e.g. `(list 'assertz clause)` passed to QUERY-PROLOG), not
  ;; functions callable on their own -- importing them is what makes the
  ;; bare token `assertz` read as the same symbol cl-prolog-kit's builtin
  ;; dispatch expects, per cl-prolog-kit's own "builtin goal names" export
  ;; section.
  (:import-from #:cl-prolog-kit
                #:query-prolog
                #:assertz
                #:retract
                #:solution-binding)
  ;; cl-chip8 internals the suite exercises. These are deliberately NOT
  ;; exported -- see the export rule at the top of src/package.lisp -- so
  ;; (:use #:cl-chip8) above does not inherit them and they are named here
  ;; instead. This is the same manoeuvre, for the same reason, as the
  ;; cl-prolog-kit ASSERTZ/RETRACT clause directly above: :IMPORT-FROM gives the
  ;; test package the identical symbol object without committing the name to
  ;; the public API.
  ;;
  ;; The first group matters most. DISPLAY-CLEAR, DISPLAY-PIXEL,
  ;; DISPLAY-XOR-PIXEL, MEMORY-READ, MEMORY-WRITE and DRAW-SPRITE are Prolog
  ;; goal functors written as bare tokens inside quoted goal terms -- e.g.
  ;; `(query-prolog *rulebase* (list 'memory-write 10 200))`. Without the
  ;; import, that bare token would intern a fresh CL-CHIP8/TEST::MEMORY-WRITE
  ;; that is not EQL to the symbol DEFINE-FOREIGN-PREDICATE registered, and
  ;; the goal would fail to dispatch.
  (:import-from #:cl-chip8
                ;; Prolog goal functors (bare tokens in quoted goal terms)
                #:memory-read
                #:memory-write
                #:display-clear
                #:display-pixel
                #:display-xor-pixel
                #:draw-sprite
                ;; internal helpers called as ordinary functions
                #:check-memory-access
                #:display-mark-all-dirty!
                ;; the raw framebuffer and the hold-expiry tick: internal
                ;; because their invariants live outside them (see the
                ;; Display and Keypad notes in src/package.lisp), but the
                ;; suite drives both directly
                #:*display*
                #:keypad-step!
                #:read-file-bytes
                #:regular-file-p
                #:check-regular-rom-file
                ;; terminal-layer keypad translation
                #:+key-hold-ticks+
                #:key-event->chip8-key
                #:keypad-apply-key-event!
                #:keypad-apply-key-events!
                #:quit-key-event-p
                ;; sub-step renderers and playfield layout
                #:+playfield-origin-x+
                #:+playfield-origin-y+
                #:half-block-character
                #:render-display-into-screen!
                #:render-sound-indicator-into-screen!
                ;; render-pipeline tuning knobs and telemetry counters
                #:chip8-render-pipeline-parallelism
                #:chip8-render-pipeline-parallel-threshold
                #:chip8-render-pipeline-shutdown-timeout
                #:chip8-render-pipeline-submitted-rows
                #:chip8-render-pipeline-completed-rows
                #:chip8-render-pipeline-serial-rows
                #:chip8-render-pipeline-queue-depth
                #:chip8-render-pipeline-high-water-mark
                ;; app struct internals
                #:make-chip8-app)
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
