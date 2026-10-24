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

  ;; One row per schema key, plus the positive-integer boundary below one.
  ;; Each row must signal through the real TOML loading path and identify the
  ;; schema path, so a table entry cannot pass by merely returning a value.
  (it "rejects every invalid configuration key value"
    (dolist (case
             '(("profile type" "[chip8]~%quirks = ~S" "legacy"
                "chip8.quirks" "profile must be modern or cosmac-vip")
               ("clock type" "[chip8]~%clock_hz = ~S" "fast"
                "chip8.clock_hz" "expected a positive integer")
               ("clock range" "[chip8]~%clock_hz = 0" nil
                "chip8.clock_hz" "expected a positive integer")
               ("display wait type" "[chip8]~%display_wait = ~S" "yes"
                "chip8.display_wait" "expected a boolean")
               ("clipping enum" "[chip8]~%clipping = ~S" "diagonal"
                "chip8.clipping" "invalid value")
               ("shift source enum" "[chip8]~%shift_source = ~S" "vz"
                "chip8.shift_source" "invalid value")
               ("BNNN register enum" "[chip8]~%bnnn_register = ~S" "vy"
                "chip8.bnnn_register" "invalid value")
               ("FX0A completion enum" "[chip8]~%fx0a_completion = ~S" "hold"
                "chip8.fx0a_completion" "invalid value")
               ("memory I enum" "[chip8]~%memory_i = ~S" "reset"
                "chip8.memory_i" "invalid value")
               ("VF reset enum" "[chip8]~%vf_reset = ~S" "clear"
                "chip8.vf_reset" "invalid value")
               ("logging path type" "[logging]~%path = 7" nil
                "logging.path" "expected a string")))
      (destructuring-bind (label control arg expected-path expected-reason) case
        (%with-toml-file (path control arg)
          (let ((condition (%signalled-config-error
                            (lambda () (cl-chip8:load-chip8-config-file path)))))
            (expect (list label (typep condition 'cl-chip8:chip8-config-error))
                    :to-equal (list label t))
            (expect (cl-chip8:chip8-config-error-path condition)
                    :to-equal expected-path)
            (expect (cl-chip8:chip8-config-error-reason condition)
                    :to-equal expected-reason))))))

  ;; The TOML override names are intentionally different from the structure
  ;; accessors. This table proves that every registered override reaches its
  ;; corresponding observable slot on the resulting quirks object.
  (it "applies every TOML quirks override slot"
    (dolist (case
             '(("vf_reset" chip8-quirks-vf-behavior "reset" :reset)
               ("memory_i" chip8-quirks-memory-i "increment" :increment)
               ("display_wait" chip8-quirks-display-wait t :wait)
               ("clipping" chip8-quirks-clipping "wrap" :wrap)
               ("shift_source" chip8-quirks-shift-source "vy" :vy)
               ("bnnn_register" chip8-quirks-bnnn-register "vx" :vx)
               ("fx0a_completion" chip8-quirks-fx0a-completion "release" :release)))
      (destructuring-bind (key accessor value expected) case
        (let* ((toml (%config-toml key value))
               (config (cl-chip8:merge-chip8-config
                        :toml toml
                        :defaults '(:quirks "modern"))))
          (expect (list key (funcall accessor (cl-chip8:chip8-config-quirks config)))
                  :to-equal (list key expected))))))

(it "defaults every CHIP-8 quirk profile from the compatibility matrix"
  ;; Timendus labels SCHIP_MODERN and SCHIP_LEGACY; these map to :schip and
  ;; :schip-legacy. Both expect I unchanged in 5-quirks. The pinned database
  ;; maps chip48 and superchip1 to increment-X. :schip-legacy follows
  ;; Timendus; P4b must apply :increment-x as a per-ROM override for records
  ;; on those database platforms.
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/src/tests/5-quirks.8o#L402-L431
  ;; https://github.com/chip-8/chip-8-database/blob/4b2a2a33f3392d813e8be4c7b955838d0797b425/database/platforms.json#L73-L123
  ;; https://github.com/chip-8/chip-8-database/blob/4b2a2a33f3392d813e8be4c7b955838d0797b425/database/quirks.json#L11-L24
  ;; Timendus expects display wait ON for CHIP-8, NONE for modern SCHIP/XO,
  ;; and LRES for legacy. README says NONE disables it in both modes and LRES
  ;; enables it only in lores; these results map to :wait, :none, :lores-only.
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/src/tests/5-quirks.8o#L437-L454
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/README.md#L361-L371
  ;; Timendus CHIP-8/SCHIP reports ON or BOTH; database wrap:false maps to
  ;; :clip. XO NONE and database wrap:true map to :wrap.
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/src/tests/5-quirks.8o#L469-L486
  ;; https://github.com/chip-8/chip-8-database/blob/4b2a2a33f3392d813e8be4c7b955838d0797b425/database/platforms.json#L1-L167
  ;; https://github.com/chip-8/chip-8-database/blob/4b2a2a33f3392d813e8be4c7b955838d0797b425/database/quirks.json#L26-L31
  ;; Gulrak Quirk 10 (opcode-table JSON ID 9) counts colliding rows plus
  ;; clipped rows for original SCHIP 1.1 hires draws. :schip-legacy models
  ;; that hardware and uses :row-count; :flag elsewhere is a baseline assumption.
  ;; https://chip8.gulrak.net/
  ;; https://chip8.gulrak.net/data/opcode-table.json
  ;; Timendus maps SUPER-CHIP MODERN (:schip) to full-pixel and LEGACY
  ;; (:schip-legacy) to half-pixel; XO routines also use full-pixel scrolling.
  ;; CHIP-8 is outside the test, so :modern and :cosmac-vip use an assumed
  ;; :full baseline.
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/src/tests/8-scrolling.8o#L96-L161
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/src/tests/8-scrolling.8o#L280-L405
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/src/tests/8-scrolling.8o#L412-L443
  ;; https://github.com/Timendus/chip8-test-suite/blob/cb24d5595384a80b49ddedae13bec4042b16d41d/README.md#L483-L494
  ;; Gulrak public generated opcode table (not pinned) lists DXY0 as 16x16
  ;; for SCHIP-MODERN and XO; Quirk 11 (opcode JSON ID 10) narrows original
  ;; SCHIP 1.x lores draws to 8x16. :schip and :xo-chip use the listed rows;
  ;; :schip-legacy uses :8x16. :modern uses a baseline-derived :16x16
  ;; default without a CHIP-8 row; :cosmac-vip :16x16 is unused because
  ;; COSMAC does not use DXY0.
  ;; https://chip8.gulrak.net/
  ;; https://chip8.gulrak.net/data/opcode-table.json
  ;; Gulrak Quirk 3 (opcode-table JSON ID 2) says original SCHIP-1.x does
  ;; not clear on mode change, so :schip-legacy uses false. True for :modern,
  ;; :cosmac-vip, :schip, and :xo-chip are baseline assumptions.
  (dolist (expected
           (list
            (list :profile :modern
                  :vf-behavior :preserve :memory-i :preserve
                  :display-wait :none :clipping :clip :shift-source :vx
                  :bnnn-register :v0 :fx0a-completion :press
                  :lores-sprite :16x16 :collision :flag
                  :lores-scroll :full :mode-switch-clear t)
            (list :profile :cosmac-vip
                  :vf-behavior :reset :memory-i :increment
                  :display-wait :wait :clipping :clip :shift-source :vy
                  :bnnn-register :v0 :fx0a-completion :release
                  :lores-sprite :16x16 :collision :flag
                  :lores-scroll :full :mode-switch-clear t)
            (list :profile :schip
                  :vf-behavior :preserve :memory-i :preserve
                  :display-wait :none :clipping :clip :shift-source :vy
                  :bnnn-register :vx :fx0a-completion :press
                  :lores-sprite :16x16 :collision :flag
                  :lores-scroll :full :mode-switch-clear t)
            (list :profile :schip-legacy
                  :vf-behavior :preserve :memory-i :preserve
                  :display-wait :lores-only :clipping :clip :shift-source :vy
                  :bnnn-register :vx :fx0a-completion :press
                  :lores-sprite :8x16 :collision :row-count
                  :lores-scroll :half :mode-switch-clear nil)
            (list :profile :xo-chip
                  :vf-behavior :preserve :memory-i :increment
                  :display-wait :none :clipping :wrap :shift-source :vx
                  :bnnn-register :v0 :fx0a-completion :press
                  :lores-sprite :16x16 :collision :flag
                  :lores-scroll :full :mode-switch-clear t)))
    (let* ((profile (getf expected :profile))
           (quirks (cl-chip8:make-chip8-quirks :profile profile)))
      (expect
       (list :profile (cl-chip8:chip8-quirks-profile quirks)
             :vf-behavior (cl-chip8:chip8-quirks-vf-behavior quirks)
             :memory-i (cl-chip8:chip8-quirks-memory-i quirks)
             :display-wait (cl-chip8:chip8-quirks-display-wait quirks)
             :clipping (cl-chip8:chip8-quirks-clipping quirks)
             :shift-source (cl-chip8:chip8-quirks-shift-source quirks)
             :bnnn-register (cl-chip8:chip8-quirks-bnnn-register quirks)
             :fx0a-completion (cl-chip8:chip8-quirks-fx0a-completion quirks)
             :lores-sprite (cl-chip8:chip8-quirks-lores-sprite quirks)
             :collision (cl-chip8:chip8-quirks-collision quirks)
             :lores-scroll (cl-chip8:chip8-quirks-lores-scroll quirks)
             :mode-switch-clear (cl-chip8:chip8-quirks-mode-switch-clear quirks))
       :to-equal expected))))

(it "preserves explicit false mode-switch-clear values through construction and merge"
  (let* ((modern (cl-chip8:make-chip8-quirks :profile :modern))
         (explicit-false
           (cl-chip8:make-chip8-quirks :profile :modern :mode-switch-clear nil))
         (merged-false
           (cl-chip8:merge-chip8-quirks modern :mode-switch-clear nil))
         (legacy-merged
           (cl-chip8:merge-chip8-quirks
            (cl-chip8:make-chip8-quirks :profile :schip-legacy))))
    (expect (list (cl-chip8:chip8-quirks-mode-switch-clear modern)
                  (cl-chip8:chip8-quirks-mode-switch-clear explicit-false)
                  (cl-chip8:chip8-quirks-mode-switch-clear merged-false)
                  (cl-chip8:chip8-quirks-mode-switch-clear legacy-merged))
            :to-equal (list t nil nil nil))))
