;;;; src/cli.lisp -- the command-line surface (cl-cli) and the executable's
;;;; entry points, mirroring cl-nyancat's own src/cli.lisp: *APP* is the
;;;; declarative spec, MAIN drives it under a normal Lisp image, and
;;;; IMAGE-ENTRY-POINT (named by :ENTRY-POINT in cl-chip8.asd) is the
;;;; toplevel of the `cl-chip8` binary `nix build` and
;;;; `(asdf:operate 'asdf:program-op ...)` both produce.
(in-package #:cl-chip8)

(defun %chip8-version ()
  "Return the running CL-CHIP8 system's :VERSION as a string, read from ASDF
rather than copied into a literal here so --version cannot drift from
cl-chip8.asd's version. Falls back to \"0.0.0\" inside a delivered image
built without installed sources."
  (let ((system (asdf:find-system "cl-chip8" nil)))
    (if system (asdf:component-version system) "0.0.0")))

(defun %run-handler (invocation)
  "The handler RUN-APP dispatches to: run the emulator from INVOCATION's
parsed ROM path and --clock-hz. RUN's own realtime loop has already stopped
and the terminal is already restored by the time this checks CHIP8-APP-ERROR
(see app.lisp's %ADVANCE-CHIP8!, which is what stops the loop cleanly on a
malformed ROM instead of an uncaught backtrace into a raw-mode terminal): a
set ERROR is reported to *ERROR-OUTPUT* and this returns 1, otherwise 0, once
the user quit normally."
  (let ((app (run :rom-path (positional-value invocation :rom)
                   :clock-hz (or (option-value invocation :clock-hz) +default-clock-hz+))))
    (if (chip8-app-error app)
        (progn
          (format *error-output* "~&cl-chip8: ~A~%" (chip8-app-error app))
          1)
        0)))

(defparameter *app*
  (make-app
   :name "cl-chip8"
   :version (%chip8-version)
   :summary "A CHIP-8 interpreter for the terminal."
   :description "Runs a CHIP-8 ROM live in the terminal. Instruction dispatch
is driven by genuine Prolog goal resolution over a cl-prolog rulebase, not a
conventional interpreter loop. Press q or Ctrl-C to quit. The keypad maps a
standard 4x4 QWERTY block onto the CHIP-8 hex keypad -- see the README."
   :positionals (list (make-positional :name "rom" :required-p t
                                       :description "Path to the CHIP-8 ROM file to run."))
   :global-options
   (list (make-option :name "clock-hz" :kind :value :type :integer :min 1
                      :description
                      (format nil "CPU instructions per second (default ~D). ~
Timers always run at a fixed 60Hz regardless."
                              +default-clock-hz+)))
   :handler #'%run-handler)
  "The declarative cl-cli specification for the `cl-chip8` command.")

(defun main ()
  "Entry point for a plain `sbcl --script'/REPL invocation. Parses the
current process argv against *APP* and exits with its result code."
  (uiop:quit (run-app *app* :argv (current-process-argv))))

(defun image-entry-point ()
  "Toplevel of the delivered `cl-chip8' executable; named by :ENTRY-POINT in
cl-chip8.asd. Identical to MAIN -- this application loads no further ASDF
systems at run time, so it needs no image-relocation bootstrapping beyond
this thin wrapper."
  (uiop:quit (run-app *app* :argv (current-process-argv))))
