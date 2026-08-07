;;;; t/cli-test.lisp
;;;;
;;;; Argument parsing and the non-terminal CLI failure boundary. RUN opens a
;;;; terminal only after loading its ROM, so a missing ROM safely exercises
;;;; the handler without entering raw mode.
(in-package #:cl-chip8/test)

(describe "the cl-chip8 app spec: --clock-hz parsing"
  (it "leaves --clock-hz unset by default"
    (let ((invocation (parse-argv *app* '("cl-chip8" "game.ch8"))))
      (expect (option-value invocation :clock-hz) :to-be-falsy)))

  (it "parses --clock-hz as an integer"
    (expect (option-value (parse-argv *app* '("cl-chip8" "--clock-hz" "500" "game.ch8"))
                          :clock-hz)
            :to-be 500))

  (it "accepts the --clock-hz :min 1 boundary value"
    (expect (option-value (parse-argv *app* '("cl-chip8" "--clock-hz" "1" "game.ch8"))
                          :clock-hz)
            :to-be 1))

  (it "rejects a --clock-hz of 0, one below the :min 1 boundary"
    (signals cli-invalid-option-value
      (parse-argv *app* '("cl-chip8" "--clock-hz" "0" "game.ch8"))))

  (it "rejects a negative --clock-hz"
    (signals cli-invalid-option-value
      (parse-argv *app* '("cl-chip8" "--clock-hz" "-1" "game.ch8"))))

  (it "rejects a non-integer --clock-hz"
    (signals cli-invalid-option-value
      (parse-argv *app* '("cl-chip8" "--clock-hz" "not-a-number" "game.ch8")))))

(describe "the cl-chip8 app spec: the rom positional"
  (it "binds the positional rom path"
    (let ((invocation (parse-argv *app* '("cl-chip8" "game.ch8"))))
      (expect (positional-value invocation :rom) :to-equal "game.ch8")))

  (it "requires the rom positional"
    (signals error (parse-argv *app* '("cl-chip8")))))

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

  (it "exits 0 on --version and prints the app's name"
    (let ((output (with-output-to-string (out)
                    (expect (run-app *app* :argv '("cl-chip8" "--version") :stdout out)
                            :to-be 0))))
      (expect (search "cl-chip8" output) :to-be-truthy)))

  (it "reports the .asd's actual :version rather than the 0.0.0 fallback"
    ;; %CHIP8-VERSION (src/cli.lisp) reads cl-chip8.asd's :version via
    ;; ASDF:FIND-SYSTEM/ASDF:COMPONENT-VERSION at load time, the same
    ;; pattern cl-nyancat's %NYANCAT-VERSION uses. This test suite runs
    ;; against cl-chip8 loaded as an installed ASDF system (not a delivered
    ;; image built without installed sources), so the fallback never applies
    ;; here -- unlike cl-nyancat's own version test, this one can assert the
    ;; exact string rather than just its shape.
    (let ((output (with-output-to-string (out)
                    (run-app *app* :argv '("cl-chip8" "--version") :stdout out))))
      (expect (search (asdf:component-version (asdf:find-system "cl-chip8")) output)
              :to-be-truthy))))
