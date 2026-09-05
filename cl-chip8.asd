;;;; cl-chip8.asd

;;; Keep the package declaration before the system definitions.
(in-package #:asdf-user)

(defsystem "cl-chip8"
  :description "A CHIP-8 (1977 COSMAC VIP instruction set) interpreter for the terminal."
  :long-description "A CHIP-8 interpreter for the terminal whose CPU state --
registers, program counter, call stack, and timers -- is expressed as a
cl-prolog-kit rulebase of dynamic facts, with instruction dispatch driven by
Prolog goal resolution rather than a conventional big-COND interpreter loop.
Memory and the display framebuffer are plain Lisp arrays for O(1) access,
wrapped by cl-prolog-kit:define-foreign-predicate so Prolog goals can still read
and write them. SBCL only."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Version consumed by flake.nix and release tooling.
  :version "0.1.2"
  :homepage "https://github.com/nerima-lisp/cl-chip8"
  :bug-tracker "https://github.com/nerima-lisp/cl-chip8/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-chip8.git")
  :depends-on ("cl-prolog-kit"  ; CPU-state rulebase and foreign predicates
               "cl-tty-kit" ; terminal input, rendering, and keypad
               "cl-cli"     ; command-line parsing
               "cl-concurrent-kit" ; render workers
               "cl-date-kit"
               "cl-host-kit"
               ;; SBCL bundled; used by ROM.LISP for regular-file checks.
               #:sb-posix)
  :pathname "src"
  :serial t
  ;; Source files live under src/.
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
  ;; Build the executable with ASDF's program-op.
  :build-operation "program-op"
  :build-pathname "cl-chip8"
  :entry-point "cl-chip8::image-entry-point"
  ;; Run the test system.
  :in-order-to ((test-op (test-op "cl-chip8/test"))))

;;; Test system.
(defsystem "cl-chip8/test"
  :description "Test system for cl-chip8."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.2"
  :homepage "https://github.com/nerima-lisp/cl-chip8"
  :bug-tracker "https://github.com/nerima-lisp/cl-chip8/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-chip8.git")
  ;; Test framework and direct test dependencies.
  :depends-on ("cl-chip8" "cl-weave" "cl-prolog-kit" "cl-tty-kit"
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
  ;; Resolve RUN-TESTS without package-qualified symbols during ASDF read.
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (funcall (find-symbol "RUN-TESTS" (find-package "CL-CHIP8/TEST")))
               (error "cl-chip8 test suite failed"))))
