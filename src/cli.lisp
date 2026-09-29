;;;; src/cli.lisp -- the command-line surface (cl-cli) and the executable's
;;;; entry points: *APP* is the declarative spec, MAIN drives it under a
;;;; normal Lisp image, and
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
  "Run the emulator selected by INVOCATION and return a shell status code.

All recoverable ROM-loading and runtime errors become a diagnostic on
*ERROR-OUTPUT* and status 1, including failures that occur before RUN can
enter its terminal session."
  (handler-case
      (let* ((options (chip8-run-options invocation))
             (cli (list :rom (getf options :rom-path)
                        :clock_hz (getf options :clock-hz)
                        :quirks (getf options :quirks)
                        :log (or (getf options :log)
                                 (getf options :log-path))))
             (config (make-chip8-config-from-sources
                      :toml-path (getf options :config-path) :cli cli))
             (logger (make-chip8-logger :path (chip8-config-log-path config)))
             (metrics (make-chip8-metrics)))
        (let ((result nil) (app nil))
          (unwind-protect
               (progn
                 (setf result
                       (handler-case
                           (progn
                             (unless (and (chip8-config-rom-path config)
                                          (probe-file (chip8-config-rom-path config)))
                               (error "ROM file does not exist: ~A"
                                      (chip8-config-rom-path config)))
                             (chip8-log-info logger "startup"
                                             (list :rom (chip8-config-rom-path config)
                                                   :clock_hz (chip8-config-clock-hz config)
                                                   :quirks (chip8-quirks-profile
                                                            (chip8-config-quirks config))))
                             (setf app (run :rom-path (chip8-config-rom-path config)
                                            :clock-hz (chip8-config-clock-hz config)
                                            :quirks (chip8-config-quirks config)))
                               (if (chip8-app-error app)
                                   (progn
                                     (chip8-log-error logger "runtime-error"
                                                      (list :error
                                                            (princ-to-string
                                                             (chip8-app-error app))))
                                     (format *error-output* "~&cl-chip8: ~A~%"
                                             (chip8-app-error app))
                                     1)
                                   0))
                         (error (condition)
                           (chip8-log-error logger "runtime-error"
                                            (list :error (princ-to-string condition)))
                           (format *error-output* "~&cl-chip8: ~A~%" condition)
                           1)))
                (chip8-log-info logger "metrics"
                                 (chip8-metrics-fields
                                  (finalize-chip8-metrics!
                                   metrics
                                   :machine (and app (chip8-app-machine app))
                                   :render-pipeline
                                   (and app (chip8-app-render-pipeline app))
                                   :effective-hz
                                   (when (and app (chip8-app-started-at app))
                                     (let ((elapsed (- (get-internal-real-time)
                                                       (chip8-app-started-at app))))
                                       (when (plusp elapsed)
                                         (float
                                          (/ (* (chip8-machine-instructions
                                                 (chip8-app-machine app))
                                                internal-time-units-per-second)
                                             elapsed))))))))
                 result)
            (flush-chip8-logger logger)
            (close-chip8-logger logger))))
    (error (condition)
      (format *error-output* "~&cl-chip8: ~A~%" condition)
      1)))

(defparameter *app*
  (make-app
   :name "cl-chip8"
   :version (%chip8-version)
   :summary "A CHIP-8 interpreter for the terminal."
   :description "Runs a CHIP-8 ROM live in the terminal. Instruction dispatch
is driven by direct typed machine dispatch, not a
conventional interpreter loop. Press Escape or Ctrl-C to quit. The keypad maps a
standard 4x4 QWERTY block onto the CHIP-8 hex keypad -- see the Terminal guide
at https://nerima-lisp.github.io/cl-chip8/guide/terminal/ for the full table."
   :positionals (list (make-positional :key :rom :name "rom" :required-p t
                                       :description "Path to the CHIP-8 ROM file to run."))
   :global-options
   (list (make-option :key :quirks :name "quirks" :kind :value
                      :choices '("modern" "cosmac-vip")
                      :description "CHIP-8 compatibility quirks profile.")
         (make-option :key :config :name "config" :kind :value
                      :description "Path to the configuration file.")
         (make-option :key :log :name "log" :kind :value
                      :description "Logging destination or level.")
         (make-option :key :clock-hz :name "clock-hz" :kind :value :type :integer :min 1
                      :description
                      (format nil "CPU instructions per second (default ~D). ~
Timers always run at a fixed 60Hz regardless."
                              +default-clock-hz+)))
   :handler #'%run-handler)
  "The declarative cl-cli specification for the `cl-chip8` command.")

(defun chip8-run-options (invocation)
  "Build the run boundary consumed by the control stream."
  (list :rom-path (positional-value invocation :rom)
        :clock-hz (option-value invocation :clock-hz)
        :quirks (option-value invocation :quirks)
        :config-path (option-value invocation :config)
        :log-path (option-value invocation :log)))

(defun main ()
  "Entry point for a plain `sbcl --script'/REPL invocation. Parses the
current process argv against *APP* and exits with its result code."
  (quit (run-app *app* :argv (current-process-argv)
                :usage-exit-code 64 :error-exit-code 1)))

(defun image-entry-point ()
  "Toplevel of the delivered `cl-chip8' executable; named by :ENTRY-POINT in
cl-chip8.asd. Identical to MAIN -- this application loads no further ASDF
systems at run time, so it needs no image-relocation bootstrapping beyond
this thin wrapper."
  (quit (run-app *app* :argv (current-process-argv)
                :usage-exit-code 64 :error-exit-code 1)))
