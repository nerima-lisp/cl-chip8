;;;; t/cli-test.lisp
;;;;
;;;; Argument parsing and the non-terminal CLI failure boundary. RUN opens a
;;;; terminal only after loading its ROM, so a missing ROM safely exercises
;;;; the handler without entering raw mode.
(in-package #:cl-chip8/test)

(defun %cli-test-script (name)
  (merge-pathnames
   (format nil "cl-chip8-cli-~A-~D.lisp" name (random 1000000))
   (uiop:temporary-directory)))

(defun %cli-sbcl-program ()
  (namestring sb-ext:*runtime-pathname*))

(defun %write-cli-test-script (path)
  (with-open-file (stream path :direction :output :if-exists :supersede)
    (format stream
            "(require :asdf)~%(let ((cache (merge-pathnames \"cl-chip8-cli-asdf/\" (uiop:temporary-directory)))) (ensure-directories-exist cache) (asdf:initialize-output-translations `(:output-translations :ignore-inherited-configuration (t (,cache :implementation)))))~%(asdf:initialize-source-registry)~%(dolist (path '~S) (pushnew path asdf:*central-registry* :test #'equal))~%(pushnew ~S asdf:*central-registry* :test #'equal)~%(asdf:load-system :cl-chip8)~%(setf sb-ext:*posix-argv* (cons \"cl-chip8\" (uiop:command-line-arguments)))~%(cl-chip8:main)~%"
            (remove nil
                    (loop for name in (asdf:registered-systems)
                          for system = (asdf:find-system name nil)
                          when system
                            collect (ignore-errors
                                      (asdf:system-source-directory system))))
            (truename #p"./")))
  path)

(defun %cli-process-result (&rest argv)
  (let ((script (%write-cli-test-script (%cli-test-script "cli"))))
    (unwind-protect
         (multiple-value-bind (output error-output exit-code)
             (uiop:run-program
              (append (list (%cli-sbcl-program) "--script" (namestring script))
                      argv)
              :output :string :error-output :string :ignore-error-status t)
           (values output error-output exit-code))
      (when (probe-file script)
        (delete-file script)))))

(describe "the cl-chip8 app spec"
  (it-each (("quirks modern" "--quirks" "modern" :quirks)
            ("quirks cosmac-vip" "--quirks" "cosmac-vip" :quirks)
            ("quirks schip" "--quirks" "schip" :quirks)
            ("quirks schip-legacy" "--quirks" "schip-legacy" :quirks)
            ("quirks xo-chip" "--quirks" "xo-chip" :quirks)
            ("platform modern" "--platform" "modern" :platform)
            ("platform cosmac-vip" "--platform" "cosmac-vip" :platform)
            ("platform schip" "--platform" "schip" :platform)
            ("platform schip-legacy" "--platform" "schip-legacy" :platform)
            ("platform xo-chip" "--platform" "xo-chip" :platform)
            ("config" "--config" "chip8.toml" :config)
            ("log" "--log" "stderr" :log)
            ("clock" "--clock-hz" "500" :clock-hz)
            ("audio" "--audio" "bell" :audio))
      "parses the ~A option"
      (label option value key)
    (declare (ignore label))
    (let ((invocation (parse-argv *app* (list "cl-chip8" option value "game.ch8"))))
      (expect (option-value invocation key) :to-equal
              (if (eq key :clock-hz) 500 value))))

  (it-each (("auto" "auto") ("pcm" "pcm") ("bell" "bell") ("off" "off"))
      "accepts --audio ~A"
      (label value)
    (declare (ignore label))
    (expect (option-value
             (parse-argv *app* (list "cl-chip8" "--audio" value "game.ch8"))
             :audio)
            :to-equal value))

  (it "rejects an unsupported --audio value"
    (expect (signals cli-invalid-option-value
                    (parse-argv *app*
                                '("cl-chip8" "--audio" "headphones" "game.ch8")))
            :to-be-truthy))

  (it "leaves optional options unset by default"
    (let ((invocation (parse-argv *app* '("cl-chip8" "game.ch8"))))
      (expect (loop for key in '(:quirks :platform :config :log :clock-hz :audio)
                    always (null (option-value invocation key)))
              :to-be t)
      (expect (getf (chip8-run-options invocation) :audio-mode)
              :to-be :auto)))

  (it-each (("zero" "--clock-hz" "0")
            ("negative" "--clock-hz" "-1")
            ("non-integer" "--clock-hz" "not-a-number")
            ("unknown profile" "--quirks" "legacy")
            ("unknown platform" "--platform" "legacy"))
      "rejects an invalid ~A value: ~A"
      (label option value)
    (declare (ignore label))
    (expect (signals cli-invalid-option-value
                    (parse-argv *app*
                                (list "cl-chip8" option value "game.ch8")))
            :to-be-truthy)))

(describe "the cl-chip8 app spec: the rom positional"
  (it "binds the positional rom path"
    (let ((invocation (parse-argv *app* '("cl-chip8" "game.ch8"))))
      (expect (positional-value invocation :rom) :to-equal "game.ch8")))

  (it "requires the rom positional"
    (signals cl-cli:cli-missing-positional (parse-argv *app* '("cl-chip8")))))

(describe "the cl-chip8 run boundary"
  (it "projects a parsed invocation into the run options plist"
    (let ((invocation
            (parse-argv *app*
                        '("cl-chip8" "--clock-hz" "321" "--quirks"
                          "cosmac-vip" "--platform" "schip" "--audio" "pcm"
                          "--config" "chip8.toml" "--log" "stderr" "game.ch8"))))
      (expect (chip8-run-options invocation)
              :to-equal
              (quote
               (:rom-path "game.ch8" :clock-hz 321 :quirks "cosmac-vip"
                :platform "schip" :colors-pixels nil :audio-mode :pcm
                :config-path "chip8.toml" :log-path "stderr"))))))

(describe "the cl-chip8 configuration error boundary"
  (it
    "turns an unreadable config path into status 1 and a diagnostic"
    (let* ((path (format nil "/tmp/cl-chip8-cli-missing-config-~D-~D.toml"
                         (get-universal-time) (random 1000000)))
           (invocation (parse-argv *app*
                                   (list "cl-chip8" "--config" path
                                         "game.ch8")))
           (output (with-output-to-string (stream)
                     (let ((*error-output* stream))
                       (expect (cl-chip8::%run-handler invocation) :to-be 1)))))
      (expect (search "cl-chip8:" output) :to-be-truthy)
      (expect (search path output) :to-be-truthy))))

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

(describe "the cl-chip8 CLI process exit boundary"
  (it "prints help and exits successfully"
    (multiple-value-bind (output error-output exit-code)
        (%cli-process-result "--help")
      (expect exit-code :to-be 0)
      (expect output :to-contain "cl-chip8")
      (expect error-output :to-equal "")))
  (it-each (("missing ROM" ("/tmp/cl-chip8-cli-no-such-rom.ch8") 1)
            ("missing option value" ("--clock-hz") 64))
      "reports ~A on stderr and exits ~D"
      (label argv expected)
    (declare (ignore label))
    (multiple-value-bind (output error-output exit-code)
        (apply #'%cli-process-result argv)
      (expect output :to-equal "")
      (expect error-output :to-contain "cl-chip8")
      (expect exit-code :to-be expected))))

(describe "the cl-chip8 CLI failure boundary"
  (it "reports a missing ROM and returns status 1 before entering the terminal"
    (let* ((path (format nil "/tmp/cl-chip8-cli-missing-rom-~D-~D.ch8"
                         (get-universal-time) (random 1000000)))
           (invocation (parse-argv *app* (list "cl-chip8" path)))
           (output (with-output-to-string (stream)
                     (let ((*error-output* stream))
                       (expect (cl-chip8::%run-handler invocation) :to-be 1)))))
      (expect (search "cl-chip8:" output) :to-be-truthy)
      (expect (search path output) :to-be-truthy)))

  (it "returns status 1 with a diagnostic when PCM initialization fails"
    (let* ((rom-path (format nil "/tmp/cl-chip8-cli-pcm-~D.ch8" (random 1000000)))
           (invocation (parse-argv *app*
                                   (list "cl-chip8" "--audio" "pcm" rom-path)))
           (selected-audio-mode nil)
           (original-run (symbol-function 'cl-chip8:run)))
      (unwind-protect
           (progn
             (with-open-file (stream rom-path :direction :output :if-exists :supersede
                                      :element-type '(unsigned-byte 8))
               (write-byte 0 stream))
             (setf (symbol-function 'cl-chip8:run)
                   (lambda (&key rom-path rom-bytes clock-hz platform quirks stream audio-mode on-audio-fallback)
                     (declare (ignore rom-path rom-bytes clock-hz platform quirks stream on-audio-fallback))
                     (setf selected-audio-mode audio-mode)
                     (error 'cl-audio-kit:audio-error :operation "open")))
             (let ((diagnostic
                     (with-output-to-string (output)
                       (let ((*error-output* output))
                         (expect (cl-chip8::%run-handler invocation) :to-be 1)))))
               (expect selected-audio-mode :to-be :pcm)
               (expect diagnostic :to-contain "cl-chip8:")))
        (setf (symbol-function 'cl-chip8:run) original-run)
        (when (probe-file rom-path) (delete-file rom-path))))))

(describe "the cl-chip8 CLI termination boundary"
  (it "logs run metrics and PCM output statistics"
    (let* ((rom-path (format nil "/tmp/cl-chip8-cli-metrics-~D.ch8" (random 1000000)))
           (log-path (format nil "/tmp/cl-chip8-cli-metrics-~D.json" (random 1000000)))
           (machine (cl-chip8:make-chip8-machine))
           (device (cl-audio-kit:make-recording-device))
           (audio-stream (cl-audio-kit:open-output-stream :device device))
           (audio-output
             (let ((output (cl-chip8::%make-chip8-audio-output
                            :stream audio-stream)))
               (setf (cl-chip8::chip8-audio-output-frames-written output) 1234)
               output))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :render-state (cl-chip8::make-chip8-render-state)
                 :audio-output audio-output
                 :started-at (- (get-internal-real-time)
                                internal-time-units-per-second)))
           (invocation (parse-argv *app*
                                   (list "cl-chip8" "--audio" "pcm"
                                         "--log" log-path rom-path)))
           (selected-audio-mode nil)
           (original-run (symbol-function 'cl-chip8:run)))
      (unwind-protect
           (progn
             (with-open-file (stream rom-path :direction :output :if-exists :supersede
                                      :element-type '(unsigned-byte 8))
               (write-byte 0 stream))
             (setf (cl-chip8:chip8-machine-instructions machine) 7)
             (setf (symbol-function 'cl-chip8:run)
                   (lambda (&key rom-path rom-bytes clock-hz platform quirks stream audio-mode on-audio-fallback)
                     (declare (ignore rom-path rom-bytes clock-hz platform quirks stream on-audio-fallback))
                     (setf selected-audio-mode audio-mode)
                     app))
             (render-chip8! (cl-tty-kit:make-screen +screen-width+ +screen-height+)
                            (cl-chip8:chip8-framebuffer-snapshot machine)
                            (cl-chip8::chip8-app-render-state app))
             (let ((error-output (make-string-output-stream)))
               (let ((*error-output* error-output))
                 (let ((status (cl-chip8::%run-handler invocation)))
                   (unless (zerop status)
                     (error "CLI handler returned ~D: ~A" status
                            (get-output-stream-string error-output))))))
             (expect selected-audio-mode :to-be :pcm)
             (multiple-value-bind (frames-written latency-seconds)
                 (cl-chip8::chip8-audio-output-stats audio-output)
               (expect frames-written :to-be 1234)
               (expect latency-seconds :to-be 0d0))
             (let ((contents (uiop:read-file-string log-path)))
               (expect (search "chip8_instructions_total" contents) :to-be-truthy)
               (expect (search ":7" contents) :to-be-truthy)
               (expect (search "chip8_render_frames_total" contents) :to-be-truthy)
               (expect (search "\"chip8_render_frames_total\":1" contents)
                       :to-be-truthy)
               (expect (search "audio-output" contents) :to-be-truthy)
               (expect (search "\"frames-written\":1234" contents)
                       :to-be-truthy)
               (expect (search "\"latency-seconds\":0.0" contents)
                       :to-be-truthy)))
        (setf (symbol-function 'cl-chip8:run) original-run)
        (when (probe-file rom-path) (delete-file rom-path))
        (when (probe-file log-path) (delete-file log-path))
        (cl-audio-kit:close-output-stream audio-stream))))
  (it "forwards platform defaults and only explicit quirks to run"
    (let* ((rom-path (format nil "/tmp/cl-chip8-cli-platform-~D.ch8" (random 1000000)))
           (log-path (format nil "/tmp/cl-chip8-cli-platform-~D.json" (random 1000000)))
           (machine (cl-chip8:make-chip8-machine))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :render-state (cl-chip8::make-chip8-render-state)
                 :started-at (- (get-internal-real-time)
                                internal-time-units-per-second)))
           (invocation (parse-argv *app*
                                   (list "cl-chip8" "--log" log-path
                                         "--platform" "schip" rom-path)))
           (explicit-invocation
             (parse-argv *app*
                         (list "cl-chip8" "--log" log-path
                               "--platform" "schip" "--quirks" "cosmac-vip"
                               rom-path)))
           (run-calls nil)
           (original-run (symbol-function 'cl-chip8:run)))
      (unwind-protect
           (progn
             (with-open-file (stream rom-path :direction :output :if-exists :supersede
                                      :element-type '(unsigned-byte 8))
               (write-byte 0 stream))
             (setf (cl-chip8:chip8-machine-instructions machine) 7)
             (setf (symbol-function 'cl-chip8:run)
                   (lambda (&key rom-path rom-bytes clock-hz platform (quirks nil quirks-p) stream audio-mode on-audio-fallback)
                     (declare (ignore rom-path rom-bytes clock-hz stream audio-mode on-audio-fallback))
                     (push (list platform quirks-p quirks) run-calls)
                     app))
             (render-chip8! (cl-tty-kit:make-screen +screen-width+ +screen-height+)
                            (cl-chip8:chip8-framebuffer-snapshot machine)
                            (cl-chip8::chip8-app-render-state app))
             (dolist (call-invocation (list invocation explicit-invocation))
               (let ((error-output (make-string-output-stream)))
                 (let ((*error-output* error-output))
                   (let ((status (cl-chip8::%run-handler call-invocation)))
                     (unless (zerop status)
                       (error "CLI handler returned ~D: ~A" status
                              (get-output-stream-string error-output)))))))
             (expect
              (reverse
               (mapcar (lambda (call)
                         (destructuring-bind (platform quirks-p quirks) call
                           (list (cl-chip8:chip8-platform-name platform)
                                 quirks-p
                                 (and quirks-p
                                      (cl-chip8:chip8-quirks-profile quirks)))))
                       run-calls))
              :to-equal '((:schip nil nil) (:schip t :cosmac-vip)))
             (let ((contents (uiop:read-file-string log-path)))
               (expect (search "chip8_instructions_total" contents) :to-be-truthy)
               (expect (search ":7" contents) :to-be-truthy)
               (expect (search "chip8_render_frames_total" contents) :to-be-truthy)
               (expect (search "\"chip8_render_frames_total\":1" contents)
                       :to-be-truthy)))
        (setf (symbol-function 'cl-chip8:run) original-run)
        (when (probe-file rom-path) (delete-file rom-path))
        (when (probe-file log-path) (delete-file log-path)))))

  (it "logs and prints one warning when automatic audio falls back"
    (let* ((rom-path (format nil "/tmp/cl-chip8-cli-audio-~D.ch8" (random 1000000)))
           (log-path (format nil "/tmp/cl-chip8-cli-audio-~D.json" (random 1000000)))
           (machine (cl-chip8:make-chip8-machine))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :render-state (cl-chip8::make-chip8-render-state)))
           (invocation (parse-argv *app*
                                   (list "cl-chip8" "--audio" "auto"
                                         "--log" log-path rom-path)))
           (selected-audio-mode nil)
           (fallback-calls 0)
           (original-run (symbol-function 'cl-chip8:run)))
      (unwind-protect
           (progn
             (with-open-file (stream rom-path :direction :output :if-exists :supersede
                                      :element-type '(unsigned-byte 8))
               (write-byte 0 stream))
             (setf (symbol-function 'cl-chip8:run)
                   (lambda (&key rom-path rom-bytes clock-hz platform quirks stream audio-mode on-audio-fallback)
                     (declare (ignore rom-path rom-bytes clock-hz platform quirks stream))
                     (setf selected-audio-mode audio-mode)
                     (expect (functionp on-audio-fallback) :to-be t)
                     (incf fallback-calls)
                     (funcall on-audio-fallback "PortAudio device unavailable")
                     app))
             (let ((diagnostic
                     (with-output-to-string (output)
                       (let ((*error-output* output))
                         (expect (cl-chip8::%run-handler invocation) :to-be 0)))))
               (expect selected-audio-mode :to-be :auto)
               (expect fallback-calls :to-be 1)
               (let ((warning-position (search "WARN" diagnostic)))
                 (expect warning-position :to-be-truthy)
                 (expect (search "WARN" diagnostic :start2 (1+ warning-position))
                         :to-be-null)))
             (let ((contents (uiop:read-file-string log-path)))
               (let ((level-position (search "WARN" contents)))
                 (expect level-position :to-be-truthy)
                 (expect (search "WARN" contents :start2 (1+ level-position))
                         :to-be-null))
               (let ((warning-position (search "audio-fallback" contents)))
                 (expect warning-position :to-be-truthy)
                 (expect (search "audio-fallback" contents
                                 :start2 (1+ warning-position))
                         :to-be-null)))
        (setf (symbol-function 'cl-chip8:run) original-run)
        (when (probe-file rom-path) (delete-file rom-path))
        (when (probe-file log-path) (delete-file log-path)))))))

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

  (it-each (("--quirks") ("--platform") ("--config") ("--log") ("--audio"))
      "lists ~A in the help output"
      (option)
    (let ((output (with-output-to-string (out)
                    (run-app *app* :argv '("cl-chip8" "--help") :stdout out))))
      (expect (search option output) :to-be-truthy)))

  (it "describes all audio modes and the default"
    (let ((output (with-output-to-string (out)
                    (run-app *app* :argv '("cl-chip8" "--help") :stdout out))))
      (expect output :to-contain "auto tries PCM and falls back to bell")
      (expect output :to-contain "pcm needs an output device")
      (expect output :to-contain "bell uses the terminal bell")
      (expect output :to-contain "off disables audio")
      (expect output :to-contain "(default auto).")))

  (it "describes --log as a file destination rather than a log level"
    (let ((output (with-output-to-string (out)
                    (run-app *app* :argv '("cl-chip8" "--help") :stdout out))))
      (expect output :to-contain "Logging destination.")
      (expect output :not :to-contain "or level")))

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

(describe "the cl-chip8 CLI resource cleanup boundary"
  (it "closes the logger when metrics initialization fails"
      (let* ((rom-path
              (merge-pathnames
               (format nil "cl-chip8-cli-metrics-fail-~D.ch8" (random 1000000))
               (uiop:temporary-directory)))
             (invocation
              (parse-argv *app* (list "cl-chip8" (namestring rom-path))))
             (closed nil)
             (original-make-metrics
              (symbol-function (quote cl-chip8::make-chip8-metrics)))
             (original-close-logger
              (symbol-function (quote cl-chip8::close-chip8-logger))))
        (unwind-protect
            (progn
              (with-open-file (stream rom-path
                                      :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create
                                      :element-type (quote (unsigned-byte 8)))
                (write-sequence
                 (make-array 0 :element-type (quote (unsigned-byte 8)))
                 stream))
              (setf (symbol-function (quote cl-chip8::make-chip8-metrics))
                    (lambda () (error "metrics initialization failed")))
              (setf (symbol-function (quote cl-chip8::close-chip8-logger))
                    (lambda (logger)
                      (declare (ignore logger))
                      (setf closed t)))
              (let ((error-output (make-string-output-stream)))
                (let ((*error-output* error-output))
                  (expect (cl-chip8::%run-handler invocation) :to-be 1)))
              (expect closed :to-be t))
          (setf (symbol-function (quote cl-chip8::make-chip8-metrics))
                original-make-metrics
                (symbol-function (quote cl-chip8::close-chip8-logger))
                original-close-logger)
          (when (probe-file rom-path)
            (delete-file rom-path)))))

  (it "closes the logger when flushing signals an error"
      (let* ((rom-path
              (merge-pathnames
               (format nil "cl-chip8-cli-flush-fail-~D.ch8" (random 1000000))
               (uiop:temporary-directory)))
             (invocation
              (parse-argv *app* (list "cl-chip8" (namestring rom-path))))
             (closed nil)
             (app
              (cl-chip8:make-chip8-app
               :machine (cl-chip8:make-chip8-machine)
               :render-state (cl-chip8::make-chip8-render-state)))
             (original-flush
              (symbol-function (quote cl-chip8::flush-chip8-logger)))
             (original-close
              (symbol-function (quote cl-chip8::close-chip8-logger)))
             (original-run (symbol-function (quote cl-chip8:run))))
        (unwind-protect
            (progn
              (with-open-file (stream rom-path
                                      :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create
                                      :element-type (quote (unsigned-byte 8)))
                (write-sequence
                 (make-array 0 :element-type (quote (unsigned-byte 8)))
                 stream))
              (setf (symbol-function (quote cl-chip8::flush-chip8-logger))
                    (lambda (logger)
                      (declare (ignore logger))
                      (error "flush failed")))
              (setf (symbol-function (quote cl-chip8::close-chip8-logger))
                    (lambda (logger)
                      (declare (ignore logger))
                      (setf closed t)))
              (setf (symbol-function (quote cl-chip8:run))
                    (lambda (&key rom-path rom-bytes clock-hz platform quirks stream
                                  audio-mode on-audio-fallback)
                      (declare (ignore rom-path rom-bytes clock-hz platform quirks
                                       stream audio-mode on-audio-fallback))
                      app))
              (let ((*error-output* (make-string-output-stream)))
                (expect (cl-chip8::%run-handler invocation) :to-be 1))
              (expect closed :to-be t))
          (setf (symbol-function (quote cl-chip8::flush-chip8-logger))
                original-flush
                (symbol-function (quote cl-chip8::close-chip8-logger))
                original-close
                (symbol-function (quote cl-chip8:run))
                original-run)
          (when (probe-file rom-path)
            (delete-file rom-path))))))

(describe "P4b ROM database CLI integration"
  (it "reports the database platform when a ROM has no supported selection"
    (let* ((bytes (make-array 1 :element-type '(unsigned-byte 8) :initial-element 0))
           (sha1 (cl-chip8::%rom-sha1 bytes))
           (rom-path
             (merge-pathnames
              (format nil "cl-chip8-p4b-unsupported-~D.ch8" (random 1000000))
              (uiop:temporary-directory)))
           (cl-chip8::*rom-database-records*
             (list (cons sha1 (quote (:platforms (:hybrid-vip))))))
           (invocation
             (parse-argv *app* (list "cl-chip8" (namestring rom-path)))))
      (unwind-protect
           (progn
             (with-open-file (stream rom-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create
                                     :element-type '(unsigned-byte 8))
               (write-sequence bytes stream))
             (let ((diagnostic
                     (with-output-to-string (output)
                       (let ((*error-output* output))
                         (expect (cl-chip8::%run-handler invocation) :to-be 1)))))
               (expect diagnostic :to-contain "unsupported platform")
               (expect diagnostic :to-contain "hybridVIP")))
        (when (probe-file rom-path)
          (delete-file rom-path)))))

  (it "logs database colors and applies them to the render palette"
    (let* ((bytes (make-array 1 :element-type '(unsigned-byte 8) :initial-element 0))
           (sha1 (cl-chip8::%rom-sha1 bytes))
           (rom-path
             (merge-pathnames
              (format nil "cl-chip8-p4b-startup-~D.ch8" (random 1000000))
              (uiop:temporary-directory)))
           (cl-chip8::*rom-database-records*
             (list
              (cons sha1
                    (quote (:platforms (:original-chip8)
                             :tickrate 7
                             :colors (:pixels ("#112233" "#ddeeff")))))))
           (invocation (parse-argv *app* (list "cl-chip8" (namestring rom-path))))
           (machine (cl-chip8:make-chip8-machine))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :render-state (cl-chip8::make-chip8-render-state)
                 :started-at (- (get-internal-real-time)
                                internal-time-units-per-second)))
           (startup-fields nil)
           (run-arguments nil)
           (original-palette (copy-seq cl-chip8::*chip8-render-palette*))
           (original-log-info (symbol-function 'cl-chip8:chip8-log-info))
           (original-run (symbol-function 'cl-chip8:run)))
      (unwind-protect
           (progn
             (with-open-file (stream rom-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create
                                     :element-type '(unsigned-byte 8))
               (write-sequence bytes stream))
             (setf (cl-chip8:chip8-machine-instructions machine) 1)
             (setf (symbol-function 'cl-chip8:chip8-log-info)
                   (lambda (logger message &optional fields)
                     (declare (ignore logger))
                     (when (string= message "startup")
                       (setf startup-fields fields))))
             (setf (symbol-function 'cl-chip8:run)
                   (lambda (&rest arguments)
                     (setf run-arguments arguments)
                     app))
             (render-chip8! (cl-tty-kit:make-screen +screen-width+ +screen-height+)
                            (cl-chip8:chip8-framebuffer-snapshot machine)
                            (cl-chip8::chip8-app-render-state app))
             (let ((error-output (make-string-output-stream)))
               (let ((*error-output* error-output))
                 (let ((status (cl-chip8::%run-handler invocation)))
                   (unless (zerop status)
                     (error "CLI handler returned ~D: ~A" status
                            (get-output-stream-string error-output))))))
             (expect (getf startup-fields :sha1) :to-equal sha1)
             (expect (getf startup-fields :clock_hz) :to-be 420)
             (expect (getf startup-fields :clock_source) :to-equal "db-rom")
             (expect (getf startup-fields :platform) :to-be :cosmac-vip)
             (expect (getf startup-fields :platform_source) :to-equal "db")
             (expect (getf startup-fields :quirks) :to-be :cosmac-vip)
             (expect (getf startup-fields :quirks_source) :to-equal "db")
             (expect (getf startup-fields :colors_pixels)
                     :to-equal "#112233,#DDEEFF")
             (expect (getf startup-fields :colors_source) :to-equal "db")
             (expect
              (equalp
               cl-chip8::*chip8-render-palette*
               (vector
                (cl-tty-kit:rgb-to-256 #x11 #x22 #x33)
                (cl-tty-kit:rgb-to-256 #xdd #xee #xff)
                (cl-tty-kit:rgb-to-256 #xdd #xee #xff)
                (cl-tty-kit:rgb-to-256 #xdd #xee #xff)))
              :to-be t)
             (expect (equalp (getf run-arguments :rom-bytes) bytes) :to-be t)
             (expect (getf run-arguments :clock-hz) :to-be 420)
             (expect (cl-chip8:chip8-platform-name
                      (getf run-arguments :platform))
                     :to-be :cosmac-vip))
        (setf (symbol-function 'cl-chip8:chip8-log-info) original-log-info
              (symbol-function 'cl-chip8:run) original-run
              cl-chip8::*chip8-render-palette* original-palette)
        (when (probe-file rom-path)
          (delete-file rom-path)))))

  (it "applies default and CLI colors to the render palette"
    (let* ((machine (cl-chip8:make-chip8-machine))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :render-state (cl-chip8::make-chip8-render-state)
                 :started-at (- (get-internal-real-time)
                                internal-time-units-per-second)))
           (startup-fields nil)
           (original-palette (copy-seq cl-chip8::*chip8-render-palette*))
           (original-log-info (symbol-function 'cl-chip8:chip8-log-info))
           (original-run (symbol-function 'cl-chip8:run)))
      (unwind-protect
           (progn
             (setf (cl-chip8:chip8-machine-instructions machine) 1)
             (setf (symbol-function 'cl-chip8:chip8-log-info)
                   (lambda (logger message &optional fields)
                     (declare (ignore logger))
                     (when (string= message "startup")
                       (setf startup-fields fields))))
             (setf (symbol-function 'cl-chip8:run)
                   (lambda (&rest arguments)
                     (declare (ignore arguments))
                     app))
             (render-chip8! (cl-tty-kit:make-screen +screen-width+ +screen-height+)
                            (cl-chip8:chip8-framebuffer-snapshot machine)
                            (cl-chip8::chip8-app-render-state app))
             (flet ((run-color-case
                        (label byte record options expected-pixels expected-source
                         expected-palette)
                      (let* ((bytes
                               (make-array 1 :element-type '(unsigned-byte 8)
                                             :initial-element byte))
                             (sha1 (cl-chip8::%rom-sha1 bytes))
                             (rom-path
                               (merge-pathnames
                                (format nil "cl-chip8-p4b-colors-~A-~D.ch8"
                                        label (random 1000000))
                                (uiop:temporary-directory)))
                             (cl-chip8::*rom-database-records*
                               (list (cons sha1 record)))
                             (invocation
                               (parse-argv
                                *app*
                                (append
                                 (list "cl-chip8" (namestring rom-path))
                                 options))))
                        (unwind-protect
                             (progn
                               (with-open-file (stream rom-path :direction :output
                                                       :if-exists :supersede
                                                       :if-does-not-exist :create
                                                       :element-type '(unsigned-byte 8))
                                 (write-sequence bytes stream))
                               (setf startup-fields nil)
                               (let ((error-output (make-string-output-stream)))
                                 (let ((*error-output* error-output))
                                   (let ((status (cl-chip8::%run-handler invocation)))
                                     (unless (zerop status)
                                       (error "CLI handler returned ~D: ~A" status
                                              (get-output-stream-string error-output))))))
                               (expect (getf startup-fields :sha1) :to-equal sha1)
                               (expect (getf startup-fields :colors_pixels)
                                       :to-equal (format nil "~{~a~^,~}" expected-pixels))
                               (expect (getf startup-fields :colors_source)
                                       :to-equal expected-source)
                               (expect
                                (equalp cl-chip8::*chip8-render-palette*
                                        expected-palette)
                                :to-be t))
                          (when (probe-file rom-path)
                            (delete-file rom-path))))))
              (run-color-case
                "db" 1
                (quote (:platforms (:original-chip8)
                         :colors (:pixels ("#123456" "#abcdef"))))
                nil
                (quote ("#123456" "#ABCDEF"))
                "db"
                (vector
                 (cl-tty-kit:rgb-to-256 #x12 #x34 #x56)
                 (cl-tty-kit:rgb-to-256 #xab #xcd #xef)
                 (cl-tty-kit:rgb-to-256 #xab #xcd #xef)
                 (cl-tty-kit:rgb-to-256 #xab #xcd #xef)))
              (run-color-case
                "default" 2
                (quote (:platforms (:original-chip8)))
                nil
                (quote ("#000000" "#00FF00" "#FFFF00" "#FFFFFF"))
                "default"
                (vector
                 (cl-tty-kit:rgb-to-256 0 0 0)
                 (cl-tty-kit:rgb-to-256 0 255 0)
                 (cl-tty-kit:rgb-to-256 255 255 0)
                 (cl-tty-kit:rgb-to-256 255 255 255)))
              (run-color-case
                "cli" 3
                (quote (:platforms (:original-chip8)
                         :colors (:pixels ("#112233" "#ddeeff"))))
                (list "--colors-pixels" "#010203,#a0b0c0")
                (quote ("#010203" "#A0B0C0"))
                "cli"
                (vector
                 (cl-tty-kit:rgb-to-256 #x01 #x02 #x03)
                 (cl-tty-kit:rgb-to-256 #xa0 #xb0 #xc0)
                 (cl-tty-kit:rgb-to-256 #xa0 #xb0 #xc0)
                 (cl-tty-kit:rgb-to-256 #xa0 #xb0 #xc0)))))
        (setf (symbol-function 'cl-chip8:chip8-log-info) original-log-info
              (symbol-function 'cl-chip8:run) original-run
              cl-chip8::*chip8-render-palette* original-palette)))))
