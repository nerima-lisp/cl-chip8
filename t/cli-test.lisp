;;;; t/cli-test.lisp
;;;;
;;;; Argument parsing and the non-terminal CLI failure boundary. RUN opens a
;;;; terminal only after loading its ROM, so a missing ROM safely exercises
;;;; the handler without entering raw mode.
(in-package #:cl-chip8/test)

(describe "the cl-chip8 app spec"
  (it-each (("quirks" "--quirks" "modern" :quirks)
            ("config" "--config" "chip8.toml" :config)
            ("log" "--log" "stderr" :log)
            ("clock" "--clock-hz" "500" :clock-hz))
      "parses the ~A option"
      (label option value key)
    (let ((invocation (parse-argv *app* (list "cl-chip8" option value "game.ch8"))))
      (expect (option-value invocation key) :to-equal
              (if (eq key :clock-hz) 500 value))))

  (it "leaves optional options unset by default"
    (let ((invocation (parse-argv *app* '("cl-chip8" "game.ch8"))))
      (expect (loop for key in '(:quirks :config :log :clock-hz)
                    always (null (option-value invocation key)))
              :to-be t)))

  (it-each (("zero" "0") ("negative" "-1") ("non-integer" "not-a-number"))
      "rejects an invalid --clock-hz value: ~A"
      (label value)
    (declare (ignore label))
    (expect (signals cli-invalid-option-value
                    (parse-argv *app* (list "cl-chip8" "--clock-hz" value "game.ch8")))
            :to-be-truthy)))

(describe "the cl-chip8 app spec: the rom positional"
  (it "binds the positional rom path"
    (let ((invocation (parse-argv *app* '("cl-chip8" "game.ch8"))))
      (expect (positional-value invocation :rom) :to-equal "game.ch8")))

  (it "requires the rom positional"
    (signals cl-cli:cli-missing-positional (parse-argv *app* '("cl-chip8")))))

(describe "the cl-chip8 CLI exit-code mapping"
  (it-each (("missing option" ("cl-chip8" "--clock-hz") 64)
            ("invalid option" ("cl-chip8" "--clock-hz" "0" "game.ch8") 64)
            ("missing ROM" ("cl-chip8" "/tmp/cl-chip8-cli-no-such-rom.ch8") 1))
      "maps ~A to exit status ~D"
      (label argv expected)
    (declare (ignore label))
    (let ((error-output (make-string-output-stream)))
      (expect (run-app *app* :argv argv :stderr error-output
                       :usage-exit-code 64 :error-exit-code 1)
              :to-be expected))))

(describe "the cl-chip8 CLI failure boundary"
  (it "reports a missing ROM and returns status 1 before entering the terminal"
    (let* ((path (format nil "/tmp/cl-chip8-cli-missing-rom-~D-~D.ch8"
                         (get-universal-time) (random 1000000)))
           (invocation (parse-argv *app* (list "cl-chip8" path)))
           (output (with-output-to-string (stream)
                     (let ((*error-output* stream))
                       (expect (cl-chip8::%run-handler invocation) :to-be 1)))))
      (expect (search "cl-chip8:" output) :to-be-truthy)
      (expect (search path output) :to-be-truthy))))

(describe "the cl-chip8 app spec: --help and --version"
  (it "exits 0 on --help without starting the emulator"
    (let ((output (with-output-to-string (out)
                    (expect (run-app *app* :argv '("cl-chip8" "--help") :stdout out)
                            :to-be 0))))
      (expect (search "cl-chip8" output) :to-be-truthy)))

  (it "lists --clock-hz in the help output"
    (let ((output (with-output-to-string (out)
                    (run-app *app* :argv '("cl-chip8" "--help") :stdout out))))
      (expect (search "--clock-hz" output) :to-be-truthy)))

  (it-each (("--quirks") ("--config") ("--log"))
      "lists ~A in the help output"
      (option)
    (let ((output (with-output-to-string (out)
                    (run-app *app* :argv '("cl-chip8" "--help") :stdout out))))
      (expect (search option output) :to-be-truthy)))

  (it "exits 0 on --version and prints the app's name"
    (let ((output (with-output-to-string (out)
                    (expect (run-app *app* :argv '("cl-chip8" "--version") :stdout out)
                            :to-be 0))))
      (expect (search "cl-chip8" output) :to-be-truthy)))

  (it "reports the .asd's actual :version rather than the 0.0.0 fallback"
    ;; The test suite runs against cl-chip8 as an installed ASDF system, so
    ;; the fallback for images built without installed sources does not apply.
    (let ((output (with-output-to-string (out)
                    (run-app *app* :argv '("cl-chip8" "--version") :stdout out))))
      (expect (search (asdf:component-version (asdf:find-system "cl-chip8")) output)
              :to-be-truthy))))
