;;;; Configuration precedence and the diagnostics contract.
;;;;
;;;; Every value error raised from a TOML file must name the file and the key
;;;; path it came from, so the diagnostics table asserts the condition's
;;;; accessors directly rather than the rendered report. The report itself is
;;;; pinned separately, because a mis-aritied :report control string leaves
;;;; every accessor correct while printing an incomplete message.
(in-package #:cl-chip8/test)

(defvar *config-temp-file-count* 0)

(defun %config-table (&rest pairs)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on pairs by #'cddr do (setf (gethash key table) value))
    table))

(defun %config-toml (name value)
  "Return the table MERGE-CHIP8-CONFIG sees for one file, holding NAME = VALUE
in the section the schema places NAME in: the document root for rom, [chip8]
for every other key. A NIL VALUE leaves the section out entirely."
  (let ((table (make-hash-table :test #'equal)))
    (when value
      (if (string= name "rom")
          (setf (gethash "rom" table) value)
          (setf (gethash "chip8" table) (%config-table name value))))
    table))

(defun %resolved-quirks-profile (config)
  (cl-chip8:chip8-quirks-profile (cl-chip8:chip8-config-quirks config)))

(defmacro %with-toml-file ((path control &rest args) &body body)
  "Write CONTROL, a FORMAT control for ARGS, to PATH's file, run BODY against
it, and delete the file however BODY ends. The name is unique for the whole
run, so two cases never share a file."
  (let ((pathname (gensym "PATHNAME")))
    `(let ((,pathname (merge-pathnames
                      (format nil "cl-chip8-config-~D.toml"
                              (incf *config-temp-file-count*))
                      (uiop:temporary-directory))))
       (unwind-protect
            (progn
              (with-open-file (stream ,pathname :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create)
                (format stream ,control ,@args)
                (terpri stream))
              (let ((,path ,pathname)) ,@body))
         (when (probe-file ,pathname)
           (delete-file ,pathname))))))

(defun %signalled-config-error (thunk)
  "Return the CHIP8-CONFIG-ERROR THUNK signals, failing the test when it
signals none instead."
  (handler-case
      (progn (funcall thunk)
             (cl-weave:fail "expected cl-chip8:chip8-config-error, but the load succeeded"))
    (cl-chip8:chip8-config-error (condition) condition)))

(describe "CHIP-8 configuration"
  (it "reports the source file and key when TOML lacks key positions"
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-unknown-key-~D.toml" (random 1000000))
                 (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (with-open-file (stream path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-string (format nil "[chip8]~%unknown = true~%") stream))
             (let ((condition (handler-case
                                  (cl-chip8:load-chip8-config-file path)
                                (cl-chip8:chip8-config-error (condition)
                                  condition))))
               (expect condition :to-be-type-of 'cl-chip8:chip8-config-error)
               (expect (cl-chip8:chip8-config-error-line condition) :to-be nil)
               (expect (cl-chip8:chip8-config-error-path condition)
                       :to-equal "chip8.unknown")
               (expect (princ-to-string condition) :to-contain (namestring path))
               (expect (princ-to-string condition)
                       :to-contain "does not retain source positions")))
        (when (probe-file path) (delete-file path)))))
  (it "uses the shared clock default"
    (let ((config (cl-chip8:merge-chip8-config)))
      (expect (cl-chip8:chip8-config-clock-hz config)
              :to-be cl-chip8::+default-clock-hz+)
      (expect (cl-chip8:chip8-app-clock-hz (cl-chip8:make-chip8-app))
              :to-be cl-chip8::+default-clock-hz+)))

  (it "keeps the app predicate internal"
    (expect (nth-value 1 (find-symbol "CHIP8-APP-P" :cl-chip8))
            :to-be :internal))

  (it-each ((700 700) (1200 1200))
      "takes the TOML clock_hz value ~A over the configured default"
      (value expected)
    (let* ((chip8 (%config-table "clock_hz" value))
           (config (cl-chip8:merge-chip8-config
                    :defaults '(:rom "default.ch8" :clock_hz 600)
                    :toml (%config-table "chip8" chip8))))
      (expect (cl-chip8:chip8-config-clock-hz config) :to-be expected)
      ;; The TOML value is only distinguishable from the default if it differs
      ;; from it, so a merge that ignored the TOML table would fail here.
      (expect (cl-chip8:chip8-config-clock-hz config) :not :to-be 600)))

  ;; One row per (key, highest-priority source that sets it). DEFAULT, TOML and
  ;; CLI are the three values offered to the merge; EXPECTED is the winner.
  (it-each (("clock_hz" cl-chip8:chip8-config-clock-hz 600 900 1100 1100)
            ("clock_hz" cl-chip8:chip8-config-clock-hz 600 900 nil 900)
            ("clock_hz" cl-chip8:chip8-config-clock-hz 600 nil nil 600)
            ("rom" cl-chip8:chip8-config-rom-path "default.ch8" "toml.ch8" "cli.ch8" "cli.ch8")
            ("rom" cl-chip8:chip8-config-rom-path "default.ch8" "toml.ch8" nil "toml.ch8")
            ("rom" cl-chip8:chip8-config-rom-path "default.ch8" nil nil "default.ch8")
            ("quirks" %resolved-quirks-profile "modern" "cosmac-vip" "cosmac-vip" :COSMAC-VIP)
            ("quirks" %resolved-quirks-profile "modern" "cosmac-vip" nil :COSMAC-VIP)
            ("quirks" %resolved-quirks-profile "modern" nil nil :MODERN))
      "resolves ~A from the highest-priority source that sets it"
      (key accessor default toml cli expected)
    (let* ((keyword (intern (string-upcase key) :keyword))
           (config (cl-chip8:merge-chip8-config
                    :defaults (list keyword default)
                    :toml (%config-toml key toml)
                    :cli (and cli (list keyword cli)))))
      (expect (funcall accessor config) :to-equal expected)))

  ;; The CLI names the log destination "log"; the TOML schema names it "path".
  ;; A merge that read one key out of both sources honours neither.
  (it-each (("CLI wins over TOML" "[logging]~%path = ~S" "/tmp/cl-chip8-toml.log"
             (:log "/tmp/cl-chip8-cli.log") "/tmp/cl-chip8-cli.log")
            ("TOML alone" "[logging]~%path = ~S" "/tmp/cl-chip8-toml.log"
             nil "/tmp/cl-chip8-toml.log")
            ("CLI alone" "[chip8]~%clock_hz = 700" nil
             (:log "/tmp/cl-chip8-cli.log") "/tmp/cl-chip8-cli.log")
            ("neither source" "[chip8]~%clock_hz = 700" nil nil nil))
      "resolves the log path for the ~A case"
      (label control arg cli expected)
    (declare (ignore label))
    (%with-toml-file (path control arg)
      (expect (cl-chip8:chip8-config-log-path
               (cl-chip8:load-chip8-config-file path :cli cli))
              :to-equal expected)))

  ;; Every row is a different TOML document that must fail the same way: the
  ;; condition type, the file the value came from, and the key path within it.
  ;; The type and range rows take different inputs that happen to share a
  ;; reason, so they stay separate rows.
  (it-each (("syntax error" "[chip8]~%clock_hz =" nil nil t)
            ("type error" "[chip8]~%clock_hz = ~S" "slow" "chip8.clock_hz" nil)
            ("range error" "[chip8]~%clock_hz = 0" nil "chip8.clock_hz" nil)
            ("unknown key inside the chip8 table" "[chip8]~%clock_z = 1"
             nil "chip8.clock_z" nil)
            ("unknown key at the top level" "[nope]~%x = 1" nil "nope" nil)
            ("bad enum value" "[chip8]~%clipping = ~S" "diagonal" "chip8.clipping" nil)
            ("unknown key inside the logging table" "[logging]~%nope = 1"
             nil "logging.nope" nil)
            ("non-string logging path" "[logging]~%path = 7" nil "logging.path" nil))
      "reports the file name and key path: ~A"
      (label control arg expected-path positionedp)
    (declare (ignore label))
    (%with-toml-file (path control arg)
      (let ((condition (%signalled-config-error
                        (lambda () (cl-chip8:load-chip8-config-file path)))))
        (expect condition :to-be-type-of 'cl-chip8:chip8-config-error)
        (when condition
          (expect (cl-chip8:chip8-config-error-source-name condition)
                  :to-equal (namestring path))
          (expect (cl-chip8:chip8-config-error-path condition) :to-equal expected-path)
          (expect (cl-chip8:chip8-config-error-reason condition) :to-be-truthy)
          (if positionedp
              (progn
                (expect (cl-chip8:chip8-config-error-line condition) :to-be-truthy)
                (expect (cl-chip8:chip8-config-error-column condition) :to-be-truthy))
              (progn
                (expect (cl-chip8:chip8-config-error-line condition) :to-be-null)
                (expect (cl-chip8:chip8-config-error-column condition) :to-be-null)))))))

  (it "prints the file name, key path and reason for a bad enum value"
    (%with-toml-file (path "[chip8]~%clipping = ~S" "diagonal")
      (let ((report (princ-to-string
                     (%signalled-config-error
                      (lambda () (cl-chip8:load-chip8-config-file path))))))
        (expect report :to-contain (namestring path))
        (expect report :to-contain "chip8.clipping")
        (expect report :to-contain "invalid value"))))

  (it "prints the file name, line, column and reason for a syntax error"
    (%with-toml-file (path "[chip8]~%clock_hz =")
      (let* ((condition (%signalled-config-error
                         (lambda () (cl-chip8:load-chip8-config-file path))))
             (report (princ-to-string condition)))
        (expect report :to-contain (namestring path))
        (expect report :to-satisfy
                (lambda (text)
                  (and (search (format nil "~D" (cl-chip8:chip8-config-error-line condition))
                               text)
                       (search (format nil "~D" (cl-chip8:chip8-config-error-column condition))
                               text))))
        (expect report :to-contain (cl-chip8:chip8-config-error-reason condition))))))
