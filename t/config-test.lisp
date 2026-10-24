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
  (it "uses every selected platform's profile and tickrate"
    (dolist (case '(("cosmac-vip" :cosmac-vip 900)
                    ("modern" :modern 720)
                    ("schip" :schip 1800)
                    ("schip-legacy" :schip-legacy 1800)
                    ("xo-chip" :xo-chip 6000)))
      (destructuring-bind (name expected-profile expected-clock) case
        (let* ((config (cl-chip8:merge-chip8-config
                        :toml (%config-toml "platform" name)))
               (platform (cl-chip8:chip8-config-platform config))
               (quirks (cl-chip8:chip8-config-quirks config)))
          (expect (list (cl-chip8:chip8-platform-name platform)
                        (cl-chip8:chip8-quirks-profile quirks)
                        (cl-chip8:chip8-config-clock-hz config))
                  :to-equal
                  (list expected-profile expected-profile expected-clock))))))
  (it "honors CLI, TOML, and defaults for platform selection"
    (let* ((all-sources
             (cl-chip8:merge-chip8-config
              :defaults '(:platform "cosmac-vip" :clock_hz 111)
              :toml (%config-table
                     "chip8" (%config-table "platform" "schip" "clock_hz" 222))
              :cli '(:platform "xo-chip" :clock_hz 333)
              :db-rom-tickrate 7 :db-platform-tickrate 8))
           (toml-over-defaults
             (cl-chip8:merge-chip8-config
              :defaults '(:platform "cosmac-vip")
              :toml (%config-toml "platform" "schip")
              :db-rom-tickrate 7 :db-platform-tickrate 8))
           (defaults-only
             (cl-chip8:merge-chip8-config
              :defaults '(:platform "cosmac-vip"))))
      (expect
       (list (cl-chip8:chip8-platform-name
              (cl-chip8:chip8-config-platform all-sources))
             (cl-chip8:chip8-quirks-profile
              (cl-chip8:chip8-config-quirks all-sources))
             (cl-chip8:chip8-config-clock-hz all-sources)
             (cl-chip8:chip8-platform-name
              (cl-chip8:chip8-config-platform toml-over-defaults))
             (cl-chip8:chip8-quirks-profile
              (cl-chip8:chip8-config-quirks toml-over-defaults))
             (cl-chip8:chip8-config-clock-hz toml-over-defaults)
             (cl-chip8:chip8-platform-name
              (cl-chip8:chip8-config-platform defaults-only))
             (cl-chip8:chip8-config-clock-hz defaults-only))
       :to-equal '(:xo-chip :xo-chip 333 :schip :schip 420 :cosmac-vip 900))))
  (it "resolves clock precedence and platform tickrates"
    (expect
     (list (cl-chip8:resolve-chip8-clock-hz
            :cli-clock-hz 321 :toml-clock-hz 654
            :db-rom-tickrate 12 :db-platform-tickrate 13
            :platform-default-tickrate 30)
           (cl-chip8:resolve-chip8-clock-hz
            :toml-clock-hz 654 :db-rom-tickrate 12
            :db-platform-tickrate 13 :platform-default-tickrate 30)
           (cl-chip8:resolve-chip8-clock-hz
            :db-rom-tickrate 12 :db-platform-tickrate 13
            :platform-default-tickrate 30)
           (cl-chip8:resolve-chip8-clock-hz
            :db-platform-tickrate 13 :platform-default-tickrate 30)
           (cl-chip8:resolve-chip8-clock-hz :platform-default-tickrate 30)
           (cl-chip8:resolve-chip8-clock-hz)
           (cl-chip8:resolve-chip8-clock-hz
            :platform-default-tickrate 15 :fallback-clock-hz 600))
     :to-equal '(321 654 720 780 1800 700 900)))

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
              "chip8.quirks" "profile must be modern, cosmac-vip, schip, schip-legacy, or xo-chip")
             ("unknown platform" "[chip8]~%platform = ~S" "legacy"
              "chip8.platform" "platform must be modern, cosmac-vip, schip, schip-legacy, or xo-chip")
             ("clock type" "[chip8]~%clock_hz = ~S" "fast"
              "chip8.clock_hz" "expected a positive integer")
             ("clock range" "[chip8]~%clock_hz = 0" nil
              "chip8.clock_hz" "expected a positive integer")
             ("display wait type" "[chip8]~%display_wait = ~S" "yes"
              "chip8.display_wait" "expected a boolean or lores-only")
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
             ("lores sprite enum" "[chip8]~%lores_sprite = ~S" "32x32"
              "chip8.lores_sprite" "invalid value")
             ("collision enum" "[chip8]~%collision = ~S" "rows"
              "chip8.collision" "invalid value")
             ("lores scroll enum" "[chip8]~%lores_scroll = ~S" "pixel"
              "chip8.lores_scroll" "invalid value")
             ("mode switch clear type" "[chip8]~%mode_switch_clear = ~S" "yes"
              "chip8.mode_switch_clear" "expected a boolean")
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
             ("memory_i" chip8-quirks-memory-i "increment-x" :increment-x)
             ("memory_i" chip8-quirks-memory-i "increment" :increment)
             ("display_wait" chip8-quirks-display-wait t :wait)
             ("display_wait" chip8-quirks-display-wait nil :none)
             ("display_wait" chip8-quirks-display-wait "lores-only" :lores-only)
             ("clipping" chip8-quirks-clipping "wrap" :wrap)
             ("shift_source" chip8-quirks-shift-source "vy" :vy)
             ("bnnn_register" chip8-quirks-bnnn-register "vx" :vx)
             ("fx0a_completion" chip8-quirks-fx0a-completion "release" :release)
             ("lores_sprite" chip8-quirks-lores-sprite "8x16" :8x16)
             ("collision" chip8-quirks-collision "row-count" :row-count)
             ("lores_scroll" chip8-quirks-lores-scroll "half" :half)
             ("mode_switch_clear" chip8-quirks-mode-switch-clear nil nil)
             ("mode_switch_clear" chip8-quirks-mode-switch-clear t t)))
    (destructuring-bind (key accessor value expected) case
      (let* ((toml (%config-table "chip8" (%config-table key value)))
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
                  :display-wait :none :clipping :clip :shift-source :vx
                  :bnnn-register :vx :fx0a-completion :press
                  :lores-sprite :16x16 :collision :flag
                  :lores-scroll :full :mode-switch-clear t)
            (list :profile :schip-legacy
                  :vf-behavior :preserve :memory-i :preserve
                  :display-wait :lores-only :clipping :clip :shift-source :vx
                  :bnnn-register :vx :fx0a-completion :press
                  :lores-sprite :8x16 :collision :row-count
                  :lores-scroll :half :mode-switch-clear nil)
            (list :profile :xo-chip
                  :vf-behavior :preserve :memory-i :increment
                  :display-wait :none :clipping :wrap :shift-source :vy
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

(describe "P4b ROM database configuration"
  (it "selects the first supported database platform and records its defaults"
    (let* ((record
             (quote (:platforms (:original-chip8 :superchip)
                      :colors (:pixels ("#123456" "#abcdef")))))
           (config
             (cl-chip8:merge-chip8-config
              :rom-record record
              :rom-sha1 "d6d8efef811350e7fba6197024c4973b360749b8")))
      (expect
       (list
        (cl-chip8:chip8-platform-name (cl-chip8:chip8-config-platform config))
        (cl-chip8:chip8-config-platform-source config)
        (cl-chip8:chip8-config-clock-hz config)
        (cl-chip8:chip8-config-clock-source config)
        (cl-chip8:chip8-config-rom-sha1 config)
        (cl-chip8:chip8-config-colors-pixels config)
        (cl-chip8:chip8-config-colors-source config))
       :to-equal
       (list :cosmac-vip "db" 900 "db-platform"
             "d6d8efef811350e7fba6197024c4973b360749b8"
             (quote ("#123456" "#ABCDEF")) "db"))))

  (it "reports the winning clock source across CLI, TOML, and database defaults"
    (let* ((record (quote (:platforms (:original-chip8) :tickrate 7)))
           (no-rom-rate (quote (:platforms (:original-chip8))))
           (cli (cl-chip8:merge-chip8-config
                 :defaults (quote (:clock_hz 111))
                 :toml (%config-table "chip8" (%config-table "clock_hz" 222))
                 :cli (quote (:clock_hz 333))
                 :rom-record record))
           (toml (cl-chip8:merge-chip8-config
                  :toml (%config-table "chip8" (%config-table "clock_hz" 222))
                  :rom-record record))
           (rom-rate (cl-chip8:merge-chip8-config :rom-record record))
           (platform-rate (cl-chip8:merge-chip8-config :rom-record no-rom-rate))
           (platform-default (cl-chip8:merge-chip8-config
                              :cli (quote (:platform "schip"))))
           (fallback (cl-chip8:merge-chip8-config)))
      (expect
       (list
        (list (cl-chip8:chip8-config-clock-hz cli)
              (cl-chip8:chip8-config-clock-source cli))
        (list (cl-chip8:chip8-config-clock-hz toml)
              (cl-chip8:chip8-config-clock-source toml))
        (list (cl-chip8:chip8-config-clock-hz rom-rate)
              (cl-chip8:chip8-config-clock-source rom-rate))
        (list (cl-chip8:chip8-config-clock-hz platform-rate)
              (cl-chip8:chip8-config-clock-source platform-rate))
        (list (cl-chip8:chip8-config-clock-hz platform-default)
              (cl-chip8:chip8-config-clock-source platform-default))
        (list (cl-chip8:chip8-config-clock-hz fallback)
              (cl-chip8:chip8-config-clock-source fallback)))
       :to-equal
       (quote ((333 "cli") (222 "toml") (420 "db-rom")
               (900 "db-platform") (1800 "platform-default")
               (700 "default"))))))

  (it "rejects unsupported database platforms unless a CLI override is explicit"
    (let* ((record (quote (:platforms (:hybrid-vip))))
           (condition
             (handler-case
                 (progn
                   (cl-chip8:merge-chip8-config :rom-record record)
                   nil)
               (cl-chip8:chip8-unsupported-platform (condition) condition)))
           (platform-override
             (cl-chip8:merge-chip8-config
              :rom-record record :cli (quote (:platform "xo-chip"))))
           (quirks-override
             (cl-chip8:merge-chip8-config
              :rom-record record :cli (quote (:quirks "schip")))))
      (expect condition :to-be-type-of 'cl-chip8:chip8-unsupported-platform)
      (expect (cl-chip8:chip8-unsupported-platform-name condition)
              :to-equal "hybridVIP")
      (expect
       (list (cl-chip8:chip8-platform-name
              (cl-chip8:chip8-config-platform platform-override))
             (cl-chip8:chip8-config-platform-source platform-override)
             (cl-chip8:chip8-quirks-profile
              (cl-chip8:chip8-config-quirks quirks-override)))
       :to-equal (quote (:xo-chip "cli" :schip)))))

  (it "distinguishes a database nil quirk from an absent quirk and lets TOML override it"
    (let* ((database-nil
             (quote (:platforms (:modern-chip8)
                      :quirky-platforms (:modern-chip8 (:shift nil)))))
           (database-absent
             (quote (:platforms (:modern-chip8)
                      :quirky-platforms (:modern-chip8 nil))))
           (nil-config (cl-chip8:merge-chip8-config :rom-record database-nil))
           (absent-config
             (cl-chip8:merge-chip8-config :rom-record database-absent))
           (toml-config
             (cl-chip8:merge-chip8-config
              :toml (%config-table
                     "chip8" (%config-table "shift_source" "vy"))
              :rom-record database-nil)))
      (expect
       (list
        (cl-chip8:chip8-quirks-shift-source
         (cl-chip8:chip8-config-quirks nil-config))
        (cl-chip8:chip8-quirks-shift-source
         (cl-chip8:chip8-config-quirks absent-config))
        (cl-chip8:chip8-quirks-shift-source
         (cl-chip8:chip8-config-quirks toml-config))
        (cl-chip8:chip8-config-quirks-source toml-config))
       :to-equal (quote (:vy :vx :vy "db+toml")))))

  (it "preserves the chip48 database false-I default and does not invent it when absent"
    (let* ((database-nil
             (quote (:platforms (:chip48)
                      :quirky-platforms
                      (:chip48 (:memory-leave-i-unchanged nil)))))
           (database-absent
             (quote (:platforms (:chip48)
                      :quirky-platforms (:chip48 nil))))
           (nil-config (cl-chip8:merge-chip8-config :rom-record database-nil))
           (absent-config
             (cl-chip8:merge-chip8-config :rom-record database-absent)))
      (expect
       (list
        (cl-chip8:chip8-quirks-memory-i
         (cl-chip8:chip8-config-quirks nil-config))
        (cl-chip8:chip8-quirks-memory-i
         (cl-chip8:chip8-config-quirks absent-config)))
       :to-equal (quote (:increment-x :preserve))))))
(describe "P4b ROM database colors"
  (it "normalizes database colors into the configuration API"
    (let* ((sha1 "018442698067c95d67e27a94e6642c11f049f108")
           (record (cl-chip8:find-rom-record sha1))
           (config (cl-chip8:merge-chip8-config
                    :rom-record record :rom-sha1 sha1)))
      (expect (cl-chip8:chip8-config-rom-sha1 config) :to-equal sha1)
      (expect
       (list (cl-chip8:chip8-config-colors-pixels config)
             (cl-chip8:chip8-config-colors-source config))
       :to-equal
       (quote (("#274A17" "#00F80A") "db")))))

  (it "rejects invalid colors from a database record"
    (let ((condition
            (%signalled-config-error
             (lambda ()
               (cl-chip8:merge-chip8-config
                :rom-record
                (quote (:platforms (:modern-chip8)
                         :colors (:pixels ("#GGGGGG" "#123456")))))))))
      (expect (cl-chip8:chip8-config-error-source-name condition)
              :to-equal "ROM database")
      (expect (cl-chip8:chip8-config-error-path condition)
              :to-equal "colors.pixels")
      (expect (cl-chip8:chip8-config-error-reason condition)
              :to-equal "expected two or four #RRGGBB colors")))

  (it "resolves colors from CLI before TOML, database, and defaults"
    (let* ((record
             (quote (:platforms (:modern-chip8)
                      :colors (:pixels ("#304050" "#c0d0e0")))))
           (cli
             (cl-chip8:merge-chip8-config
              :cli (quote (:colors_pixels ("#102030" "#a0b0c0")))
              :toml (%config-table
                     "colors" (%config-table "pixels" (quote ("#213243" "#b1c2d3"))))
              :rom-record record))
           (toml
             (cl-chip8:merge-chip8-config
              :toml (%config-table
                     "colors" (%config-table "pixels" (quote ("#213243" "#b1c2d3"))))
              :rom-record record))
           (database (cl-chip8:merge-chip8-config :rom-record record))
           (default (cl-chip8:merge-chip8-config)))
      (expect
       (list (cl-chip8:chip8-config-colors-pixels cli)
             (cl-chip8:chip8-config-colors-pixels toml)
             (cl-chip8:chip8-config-colors-pixels database)
             (cl-chip8:chip8-config-colors-pixels default))
       :to-equal
       (quote (("#102030" "#A0B0C0")
               ("#213243" "#B1C2D3")
               ("#304050" "#C0D0E0")
               ("#000000" "#00FF00" "#FFFF00" "#FFFFFF"))))
      (expect
       (list (cl-chip8:chip8-config-colors-source cli)
             (cl-chip8:chip8-config-colors-source toml)
             (cl-chip8:chip8-config-colors-source database)
             (cl-chip8:chip8-config-colors-source default))
       :to-equal (quote ("cli" "toml" "db" "default"))))))
