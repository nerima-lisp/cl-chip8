;;;; t/cli-test.lisp
;;;;
;;;; Argument parsing and the non-terminal CLI failure boundary. RUN opens a
;;;; terminal only after loading its ROM, so a missing ROM safely exercises
;;;; the handler without entering raw mode.
(in-package #:cl-chip8/test)

(defun %pty-test-script (name)
  (merge-pathnames
   (format nil "cl-chip8-pty-~A-~D.lisp" name (random 1000000))
   (uiop:temporary-directory)))

(defun %pty-sbcl-program ()
  (namestring sb-ext:*runtime-pathname*))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %pty-unavailability-reason ()
    (let ((pty nil))
      (let ((reason
              (handler-case
                  (progn
                    (setf pty (cl-tty-kit:make-pty :program "/bin/sh"
                                                   :args '("-c" "exit 0")))
                    (let ((deadline (+ (get-internal-real-time)
                                       (* 2 internal-time-units-per-second))))
                      (loop while (and (cl-tty-kit:pty-alive-p pty)
                                       (< (get-internal-real-time) deadline))
                            do (sleep 0.01)))
                    (if (cl-tty-kit:pty-alive-p pty)
                        "PTY probe timed out"
                        (unless (eql (cl-tty-kit:pty-exit-code pty) 0)
                          "PTY probe process did not exit successfully")))
                (error (condition)
                  (format nil "PTY unavailable: ~A" condition)))))
        (when pty
          (ignore-errors (cl-tty-kit:close-pty pty)))
        reason))))

(defmacro %it-pty-isolated (name &body body)
  (let ((options (first body))
        (forms (rest body)))
    `(cl-weave:it-isolated ,name ,options
       (let ((reason (%pty-unavailability-reason)))
         (if reason
             (skip reason)
             (progn ,@forms))))))

(defun %write-pty-test-script (path)
  (with-open-file (stream path :direction :output :if-exists :supersede)
    (format stream
            "(require :asdf)~%(let ((cache (merge-pathnames \"cl-chip8-pty-asdf/\" (uiop:temporary-directory)))) (ensure-directories-exist cache) (asdf:initialize-output-translations `(:output-translations :ignore-inherited-configuration (t (,cache :implementation)))))~%(asdf:initialize-source-registry)~%(dolist (path '~S) (pushnew path asdf:*central-registry* :test #'equal))~%(pushnew ~S asdf:*central-registry* :test #'equal)~%(asdf:load-system :cl-chip8)~%(setf sb-ext:*posix-argv* (cons \"cl-chip8\" (uiop:command-line-arguments)))~%(cl-chip8:main)~%"
            (remove nil
                    (loop for name in (asdf:registered-systems)
                          for system = (asdf:find-system name nil)
                          when system
                            collect (ignore-errors
                                      (asdf:system-source-directory system))))
            (truename #p"./")))
  path)

(defun %pty-drain (pty output)
  (let ((chunk (ignore-errors (cl-tty-kit:pty-read pty))))
    (if chunk
        (concatenate 'string output chunk)
        output)))

(defun %pty-expect-alive (pty output)
  (let ((output (%pty-drain pty output)))
    (expect (if (cl-tty-kit:pty-alive-p pty)
                t
                (list :pty-alive-p nil
                      :pty-output output
                      :pty-exit-code (cl-tty-kit:pty-exit-code pty)))
            :to-be t)))

(defun %pty-expect-done (pty output done-p exit-code)
  (let ((output (if pty (%pty-drain pty output) output)))
    (expect (if done-p
                t
                (list :done-p done-p
                      :pty-output output
                      :pty-alive-p (and pty (cl-tty-kit:pty-alive-p pty))
                      :pty-exit-code (or exit-code
                                         (and pty
                                              (cl-tty-kit:pty-exit-code pty)))))
            :to-be t)))

(defun %pty-read-until (pty predicate &key (timeout 60))
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second)))
        (output ""))
    (loop
      (let ((chunk (ignore-errors (cl-tty-kit:pty-read pty))))
        (when chunk
          (setf output (concatenate 'string output chunk))))
      (when (funcall predicate output)
        (return (values output t)))
      (unless (cl-tty-kit:pty-alive-p pty)
        (loop repeat 20
              for chunk = (ignore-errors (cl-tty-kit:pty-read pty))
              do (when chunk
                   (setf output (concatenate 'string output chunk)))
                 (sleep 0.01))
        (return (values output nil)))
      (when (>= (get-internal-real-time) deadline)
        (return (values output nil)))
      (sleep 0.01))))

(defun %pty-wait-for-exit (pty &key (timeout 60))
  (multiple-value-bind (output ready-p)
      (%pty-read-until pty (lambda (text) (declare (ignore text))
                             (not (cl-tty-kit:pty-alive-p pty)))
                        :timeout timeout)
    (values output ready-p (cl-tty-kit:pty-exit-code pty))))

(defun %pty-wait-for-terminal (pty &key (timeout 60))
  (%pty-read-until pty
                   (lambda (text)
                     (search (format nil "~C[?1049h" #\Escape) text))
                   :timeout timeout))

(defmacro %with-test-pty ((var &rest options) &body body)
  `(let ((,var nil)
         (reason nil))
     (handler-case
         (setf ,var (cl-tty-kit:make-pty
                     :environment (sb-ext:posix-environ)
                     ,@options))
       (error (condition)
         (setf reason (format nil "PTY unavailable: ~A" condition))))
     (if reason
         (skip reason)
         (unwind-protect
              (progn ,@body)
           (when ,var
             (ignore-errors (cl-tty-kit:close-pty ,var)))))))

(defun %cli-pty-result (&rest argv)
  (let ((script (%write-pty-test-script (%pty-test-script "cli"))))
    (unwind-protect
         (%with-test-pty (pty :program (%pty-sbcl-program)
                               :args (cons "--script"
                                           (cons (namestring script) argv)))
           (%pty-wait-for-exit pty))
      (when (probe-file script)
        (delete-file script)))))

(describe "the cl-chip8 app spec"
  (it-each (("quirks" "--quirks" "modern" :quirks)
            ("config" "--config" "chip8.toml" :config)
            ("log" "--log" "stderr" :log)
            ("clock" "--clock-hz" "500" :clock-hz))
      "parses the ~A option"
      (label option value key)
    (declare (ignore label))
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

(describe "the cl-chip8 run boundary"
  (it
    "projects a parsed invocation into the pure run options plist"
    (let ((invocation
            (parse-argv *app*
                        '("cl-chip8" "--clock-hz" "321" "--quirks"
                          "cosmac-vip" "--config" "chip8.toml" "--log"
                          "stderr" "game.ch8"))))
      (expect (chip8-run-options invocation)
              :to-equal
              '(:rom-path "game.ch8" :clock-hz 321 :quirks "cosmac-vip"
                :config-path "chip8.toml" :log-path "stderr")))))

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

(%it-pty-isolated "PTY CLI --help exits successfully"
    (:systems ("cl-chip8/test") :timeout 60)
  (multiple-value-bind (output done-p exit-code)
      (%cli-pty-result "--help")
    (%pty-expect-done nil output done-p exit-code)
    (expect exit-code :to-be 0)
    (expect output :to-contain "cl-chip8")))

(%it-pty-isolated "PTY CLI missing ROM exits 1"
    (:systems ("cl-chip8/test") :timeout 60)
  (multiple-value-bind (output done-p exit-code)
      (%cli-pty-result "/tmp/cl-chip8-pty-no-such-rom.ch8")
    (%pty-expect-done nil output done-p exit-code)
    (expect exit-code :to-be 1)
    (expect output :to-contain "cl-chip8:")))

(%it-pty-isolated "PTY CLI missing option value exits 64"
    (:systems ("cl-chip8/test") :timeout 60)
  (multiple-value-bind (output done-p exit-code)
      (%cli-pty-result "--clock-hz")
    (%pty-expect-done nil output done-p exit-code)
    (expect exit-code :to-be 64)
    (expect output :to-contain "cl-chip8")))

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

(describe "the cl-chip8 CLI termination boundary"
  (it "logs a non-zero instruction count when run returns"
    (let* ((rom-path (format nil "/tmp/cl-chip8-cli-metrics-~D.ch8" (random 1000000)))
           (log-path (format nil "/tmp/cl-chip8-cli-metrics-~D.json" (random 1000000)))
           (machine (cl-chip8:make-chip8-machine))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :render-state (cl-chip8::make-chip8-render-state)
                 :started-at (- (get-internal-real-time)
                                internal-time-units-per-second)))
           (invocation (parse-argv *app*
                                   (list "cl-chip8" "--log" log-path rom-path)))
           (original-run (symbol-function 'cl-chip8:run)))
      (unwind-protect
           (progn
             (with-open-file (stream rom-path :direction :output :if-exists :supersede
                                      :element-type '(unsigned-byte 8))
               (write-byte 0 stream))
             (setf (cl-chip8:chip8-machine-instructions machine) 7)
             (setf (symbol-function 'cl-chip8:run)
                   (lambda (&key rom-path clock-hz quirks stream)
                     (declare (ignore rom-path clock-hz quirks stream))
                     app))
             (render-chip8! (cl-tty-kit:make-screen +screen-width+ +screen-height+)
                            (chip8-machine-framebuffer machine)
                            (cl-chip8::chip8-app-render-state app))
             (let ((error-output (make-string-output-stream)))
               (let ((*error-output* error-output))
                 (let ((status (cl-chip8::%run-handler invocation)))
                   (unless (zerop status)
                     (error "CLI handler returned ~D: ~A" status
                            (get-output-stream-string error-output))))))
             (let ((contents (uiop:read-file-string log-path)))
               (expect (search "chip8_instructions_total" contents) :to-be-truthy)
               (expect (search ":7" contents) :to-be-truthy)
               (expect (search "chip8_render_frames_total" contents) :to-be-truthy)
               (expect (search "\"chip8_render_frames_total\":1" contents)
                       :to-be-truthy)))
        (setf (symbol-function 'cl-chip8:run) original-run)
        (when (probe-file rom-path) (delete-file rom-path))
        (when (probe-file log-path) (delete-file log-path))))))

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
