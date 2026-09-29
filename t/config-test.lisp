;;;; Configuration precedence and diagnostics.
(in-package #:cl-chip8/test)

(defun %config-table (&rest pairs)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on pairs by #'cddr do (setf (gethash key table) value))
    table))

(describe "CHIP-8 configuration"
  (it-each ((700 700) (1200 1200))
      "takes the TOML clock_hz value: ~A"
      (value expected)
    (let* ((chip8 (%config-table "clock_hz" value))
           (config (cl-chip8:merge-chip8-config
                    :defaults '(:rom "default.ch8" :clock_hz 600)
                    :toml (%config-table "chip8" chip8))))
      (expect (cl-chip8:chip8-config-clock-hz config) :to-be expected)))

  (it "applies CLI over TOML over defaults"
    (let* ((chip8 (%config-table "quirks" "cosmac-vip" "clock_hz" 900))
           (config (cl-chip8:merge-chip8-config
                    :defaults '(:rom "default.ch8" :clock_hz 600)
                    :toml (%config-table "chip8" chip8)
                    :cli '(:rom "cli.ch8" :clock_hz 1100))))
      (expect (cl-chip8:chip8-config-rom-path config) :to-equal "cli.ch8")
      (expect (cl-chip8:chip8-config-clock-hz config) :to-be 1100)))

  (it-each ((:unknown '(:wat 1)) (:range '(:clock_hz 0)))
      "signals chip8-config-error for ~A"
      (kind source)
    (declare (ignore kind))
    (expect (signals cl-chip8:chip8-config-error
                    (cl-chip8:merge-chip8-config :cli source)) :to-be-truthy))

  (it-each (("[chip8]~%clock_hz =" "syntax")
            ("[chip8]~%clock_hz = \"slow\"" "type"))
      "diagnoses a malformed TOML file: ~A"
      (content kind)
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-config-~A-~D.toml" kind (random 1000000))
                 (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (with-open-file (stream path :direction :output :if-exists :supersede)
               (format stream content))
             (handler-case
                 (progn (cl-chip8:load-chip8-config-file path)
                        (error "expected config error"))
               (cl-chip8:chip8-config-error (condition)
                 (expect (search (namestring path)
                                 (princ-to-string condition)) :to-be-truthy)
                 (when (string= kind "syntax")
                   (expect (cl-chip8:chip8-config-error-line condition) :to-be-truthy)))))
        (when (probe-file path) (delete-file path))))))
