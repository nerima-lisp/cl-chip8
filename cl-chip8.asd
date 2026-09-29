;;;; cl-chip8.asd

;;; Keep the package declaration before the system definitions.
(in-package #:asdf-user)

(defsystem "cl-chip8"
  :description "A CHIP-8 (1977 COSMAC VIP instruction set) interpreter for the terminal."
  :long-description "A CHIP-8 interpreter for the terminal with a typed machine state and direct opcode dispatch. SBCL only."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Version consumed by flake.nix and release tooling.
  :version "0.2.0"
  :homepage "https://github.com/nerima-lisp/cl-chip8"
  :bug-tracker "https://github.com/nerima-lisp/cl-chip8/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-chip8.git")
  :depends-on ("cl-tty-kit"
               "cl-dataflow-kit"
               "cl-cli"     ; command-line parsing
               "cl-toml-kit"
               "cl-log-kit"
               "cl-observability-kit"
               "cl-concurrent-kit" ; render workers
               "cl-date-kit"
               "cl-host-kit"
               ;; SBCL bundled; used by ROM.LISP for regular-file checks.
               #:sb-posix)
  :pathname "src"
  :serial t
  ;; Source files live under src/.
  :components ((:file "package") (:file "conditions") (:file "config")
               (:file "logging") (:file "metrics") (:file "types") (:file "quirks")
               (:file "machine-types") (:file "machine") (:file "memory") (:file "fontset")
               (:file "display-types") (:file "display") (:file "opcode-data")
               (:file "opcode-execution") (:file "opcode-dispatch") (:file "opcode-cps")
               (:file "timers") (:file "keypad") (:file "rom") (:file "headless")
               (:file "render-types")
               (:file "render")
               (:file "concurrent-render-types")
               (:file "concurrent-render-macros")
               (:file "concurrent-render") (:file "concurrent-render-rows")
               (:file "control-events")
               (:file "state-machine")
               (:file "app-types")
               (:file "control-cps")
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
  :version "0.2.0"
  :homepage "https://github.com/nerima-lisp/cl-chip8"
  :bug-tracker "https://github.com/nerima-lisp/cl-chip8/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-chip8.git")
  ;; Test framework and direct test dependencies.
  :depends-on ("cl-chip8" "cl-weave" "cl-tty-kit"
               "cl-toml-kit" "cl-log-kit" "cl-observability-kit"
               "cl-concurrent-kit"
               "cl-json-kit"
               "cl-date-kit"
               "cl-host-kit")
  :pathname "t"
  :serial t
  :components ((:file "package") (:file "cpu-test") (:file "memory-test")
               (:file "display-test") (:file "fontset-test") (:file "keypad-test")
               (:file "timers-test") (:file "rom-test")
               (:file "render-test") (:file "concurrency-test")
               (:file "corpus-test")
               (:file "config-test") (:file "cli-test")
               (:file "logging-metrics-test") (:file "app-test")
               (:file "state-machine-test"))
               (:file "timendus-test") (:file "benchmark-test"))
  ;; Resolve RUN-TESTS without package-qualified symbols during ASDF read.
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (funcall (find-symbol "RUN-TESTS" (find-package "CL-CHIP8/TEST")))
               (error "cl-chip8 test suite failed"))))
