;;;; cl-chip8.asd

;;; This form comes FIRST, before any defsystem. ASDF binds *package* to
;;; ASDF-USER only for a file it loads itself; read any other way -- a REPL
;;; `load`, an editor evaluating the buffer, flake.nix parsing :version --
;;; the file is read in whatever package happens to be current, and an
;;; unqualified `defsystem` then fails to read at all. See
;;; PACKAGE_STANDARD.md "asd の書き方".
;;;
;;; No sibling package's prefix (cl-prolog:, cl-tty-kit:, cl-cli:,
;;; cl-chip8/test:) may appear anywhere below. :DEPENDS-ON is not processed
;;; until the whole file has been READ, so a qualified symbol naming a
;;; package that does not exist yet is a hard read-time error, not a
;;; load-time one. The :PERFORM clause at the bottom therefore reaches its
;;; test runner through FIND-PACKAGE / FIND-SYMBOL / FUNCALL, all of which
;;; are CL symbols. See ADR-0081.
(in-package #:asdf-user)

(defsystem "cl-chip8"
  :description "A CHIP-8 (1977 COSMAC VIP instruction set) interpreter for the terminal."
  :long-description "A CHIP-8 interpreter for the terminal whose CPU state --
registers, program counter, call stack, and timers -- is expressed as a
cl-prolog rulebase of dynamic facts, with instruction dispatch driven by
Prolog goal resolution rather than a conventional big-COND interpreter loop.
Memory and the display framebuffer are plain Lisp arrays for O(1) access,
wrapped by cl-prolog:define-foreign-predicate so Prolog goals can still read
and write them. SBCL only."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Single source of truth for the version. flake.nix reads this form, and
  ;; release.yml refuses to publish a tag that disagrees with it.
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-chip8"
  :bug-tracker "https://github.com/nerima-lisp/cl-chip8/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-chip8.git")
  :depends-on ("cl-prolog"  ; the CPU-state rulebase: dynamic facts, assert/retract,
                            ; foreign predicates
               "cl-tty-kit" ; terminal screen/renderer/input, used by stage 2's rendering
                            ; and keypad layers
               "cl-cli"     ; command-line parsing, used by stage 2's entry point
               "cl-concurrent-kit" ; persistent executor for pure render-row work
               "cl-date-kit"
               "cl-host-kit"
               ;; SB-POSIX::STAT/S-ISREG, for ROM.LISP's REGULAR-FILE-P: SBCL-
               ;; bundled, so this does not count as an external or org-internal
               ;; dependency under CODING_STANDARD.md's SBCL-only stance -- it is
               ;; listed explicitly, mirroring cl-host-kit.asd's own
               ;; :depends-on (#:sb-posix), so load order does not silently rely
               ;; on cl-cli's transitive pull of cl-host-kit (which also depends
               ;; on it) instead.
               #:sb-posix)
  :pathname "src"
  :serial t
  ;; src/ is flat and every defpackage lives in src/package.lisp.
  :components ((:file "package")
               (:file "conditions")
               (:file "memory-types")
               (:file "memory")
               (:file "display-types")
               (:file "display")
               (:file "fontset")
               (:file "state-types")
               (:file "state")
               (:file "opcode-runtime")
               (:file "opcode-foreign")
               (:file "opcodes")
               (:file "keypad-types")
               (:file "keypad")
               (:file "timers")
               (:file "rom")
               (:file "render-types")
               (:file "render")
               (:file "concurrent-render-types")
               (:file "concurrent-render-macros")
               (:file "concurrent-render") (:file "concurrent-render-rows")
               (:file "app")
               (:file "cli"))
  ;; Delivers the `cl-chip8` executable via `(asdf:operate 'asdf:program-op
  ;; "cl-chip8")` / `nix build`, both driven from these three keys -- see
  ;; cl-nyancat.asd, which this follows, and flake.nix's `executable` block.
  :build-operation "program-op"
  :build-pathname "cl-chip8"
  :entry-point "cl-chip8::image-entry-point"
  ;; Mandatory. Without it `asdf:test-system "cl-chip8"` succeeds while
  ;; running zero tests. See PACKAGE_STANDARD.md.
  :in-order-to ((test-op (test-op "cl-chip8/test"))))

;;; The test system is `cl-chip8/test` (singular, slash-separated) with
;;; :pathname "t". It is NOT `cl-chip8-test` and NOT `cl-chip8/tests`.
(defsystem "cl-chip8/test"
  :description "Test system for cl-chip8."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-chip8"
  :bug-tracker "https://github.com/nerima-lisp/cl-chip8/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-chip8.git")
  ;; cl-weave is the org's test framework everywhere. Do not introduce FiveAM,
  ;; parachute, rove or prove.
  ;;
  ;; Test-only: cl-prolog for QUERY-PROLOG/ASSERTZ/RETRACT (t/state-test.lisp
  ;; round-trips a register fact directly), and cl-tty-kit for DECODE-INPUT
  ;; (t/keypad-test.lisp builds KEY-EVENTs from a plain string, mirroring
  ;; cl-nyancat's t/input-test.lisp) and MAKE-SCREEN/SCREEN-CELL
  ;; (t/render-test.lisp asserts on painted cells). Both are already the main
  ;; system's own dependency, at the same layer, so this stays within
  ;; DEPENDENCY_POLICY.md's test-only dependency limit.
  ;; cl-host-kit is named here because t/corpus-test.lisp calls HOST-KIT:GETENV
  ;; and the directory-tree walker directly, and run-tests.lisp LOADs the
  ;; system by name before running the suite. Inheriting it through cl-chip8
  ;; happens to work under a flat (:tree ../) source registry, which is why a
  ;; local run never complained -- but each Nix lispDerivation builds in its
  ;; own sandbox containing only its declared dependencies, so the omission
  ;; failed CI with `Component "cl-host-kit" not found`.
  :depends-on ("cl-chip8" "cl-weave" "cl-prolog" "cl-tty-kit"
               "cl-concurrent-kit"
               "cl-date-kit"
               "cl-host-kit")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "memory-test")
               (:file "display-test")
               (:file "fontset-test")
               (:file "state-test")
               (:file "helpers-opcodes")
               (:file "opcodes-flow-test")
               (:file "opcodes-alu-test")
               (:file "opcodes-memory-test")
               (:file "opcodes-io-test")
               (:file "keypad-test")
               (:file "timers-test")
               (:file "render-test")
               (:file "concurrency-test")
               (:file "rom-test")
               (:file "corpus-test")
               (:file "integration-test")
               (:file "cli-test"))
  ;; ADR-0081: no package-qualified helper call here. FIND-PACKAGE / FIND-SYMBOL / FUNCALL
  ;; are all CL symbols, so this clause reads without depending on anything
  ;; :DEPENDS-ON has not loaded yet.
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (funcall (find-symbol "RUN-TESTS" (find-package "CL-CHIP8/TEST")))
               (error "cl-chip8 test suite failed"))))
