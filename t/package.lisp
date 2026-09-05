;;;; t/package.lisp
(defpackage #:cl-chip8/test
  (:use #:cl #:cl-chip8)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.
  (:shadowing-import-from #:cl-weave #:describe)
  ;; BEFORE-EACH and SKIP are runtime suite hooks; corpus tests use SKIP after
  ;; checking the environment.
  (:import-from #:cl-weave
                #:it #:expect #:signals #:run-all #:with-soft-assertions #:before-each
                #:skip)
  ;; Test-only cl-prolog-kit primitives for querying facts in *RULEBASE*.
  (:import-from #:cl-prolog-kit
                #:query-prolog
                #:assertz
                #:retract
                #:solution-binding)
  ;; Internal symbols used by tests, including Prolog goal functors.
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
  ;; Test-only cl-tty-kit primitives for decoded input and screen assertions.
  (:import-from #:cl-tty-kit
                #:decode-input
                #:make-key-event
                #:make-screen
                #:screen-cell
                #:cell-char
                #:cell-style)
  ;; Test-only cl-cli primitives. cl-cli is already a main-system dependency,
  ;; so no test-only dependency entry is needed.
  (:import-from #:cl-cli
                #:parse-argv
                #:run-app
                #:option-value
                #:positional-value
                #:cli-invalid-option-value)
  (:export #:run-tests))

(in-package #:cl-chip8/test)

(defun run-tests (&key coverage coverage-output coverage-report-directory coverage-include-pathnames coverage-exclude-pathnames coverage-minimum-expression coverage-minimum-branch) "Run every registered spec and signal on failure so ASDF TEST-OP fails." (unless (run-all :reporter :spec :pass-with-no-tests nil :coverage coverage :coverage-output coverage-output :coverage-report-directory coverage-report-directory :coverage-include-pathnames coverage-include-pathnames :coverage-exclude-pathnames coverage-exclude-pathnames :coverage-minimum-expression coverage-minimum-expression :coverage-minimum-branch coverage-minimum-branch :coverage-reset t) (error "cl-chip8 test suite failed")) (format t "~&cl-chip8/test: successful completion with 0 failures~%") t)
