;;;; TOML configuration and precedence rules.
(in-package #:cl-chip8)

(define-condition chip8-config-error (chip8-error)
  ((source-name :initarg :source-name :initform nil :reader chip8-config-error-source-name)
   (line :initarg :line :initform nil :reader chip8-config-error-line)
   (column :initarg :column :initform nil :reader chip8-config-error-column)
   (path :initarg :path :initform nil :reader chip8-config-error-path)
   (key :initarg :key :initform nil :reader chip8-config-error-key)
   (reason :initarg :reason :initform nil :reader chip8-config-error-reason))
  (:report
   (lambda (condition stream)
     (format stream "Invalid CHIP-8 configuration~@[ in ~A~]~@[ at ~D:~D~]~@[ for ~A~]~@[; ~A~]"
             (chip8-config-error-source-name condition)
             (chip8-config-error-line condition)
             (chip8-config-error-column condition)
             (or (chip8-config-error-path condition)
                 (chip8-config-error-key condition))
             (chip8-config-error-reason condition)))))

(defparameter +default-chip8-clock-hz+ 700)

;; The schema is data; validation below is deliberately independent of it.
(defparameter +chip8-config-schema+
  '(("chip8" . (("quirks" . :profile) ("clock_hz" . :positive-integer)
                 ("display_wait" . :boolean) ("clipping" . :clipping)
                 ("shift_source" . :shift-source) ("bnnn_register" . :bnnn-register)
                 ("fx0a_completion" . :fx0a-completion)
                 ("memory_i" . :memory-i) ("vf_reset" . :vf-reset)))
    ("logging" . (("path" . :string)))))

(defstruct (chip8-config (:constructor %make-chip8-config) (:copier nil))
  rom-path clock-hz quirks log-path)

(defun %config-error (reason &key source-name line column path key)
  (error 'chip8-config-error :reason reason :source-name source-name
         :line line :column column :path path :key key))

(defun %hash-value (table key)
  (multiple-value-bind (value presentp) (gethash key table)
    (if presentp (values value t)
        (gethash (intern (string-upcase key) :keyword) table))))

(defun %source-value (source key)
  (cond
    ((null source) (values nil nil))
    ((hash-table-p source) (%hash-value source key))
    ((listp source)
     (let ((cell (member (intern (string-upcase key) :keyword) source :test #'eq)))
       (if cell (values (second cell) t) (values nil nil))))
    (t (%config-error "source must be a property list or table" :key key))))

(defun %source-keys (source)
  (cond
    ((hash-table-p source)
     (loop for key being the hash-keys of source collect (string-downcase (string key))))
    ((listp source)
     (loop for key in source by #'cddr
           collect (string-downcase (symbol-name key))))
    (t nil)))

(defun %validate-keys (source allowed source-name prefix)
  (dolist (key (%source-keys source))
    (unless (member key allowed :test #'string=)
      (%config-error "unknown key" :source-name source-name
                     :path (if prefix (format nil "~A.~A" prefix key) key)
                     :key key))))

(defun %value (sources key)
  (loop for source in (reverse sources)
        do (multiple-value-bind (value presentp) (%source-value source key)
             (when presentp (return value)))))

(defun %require-type (value predicate reason key source)
  (unless (funcall predicate value)
    (%config-error reason :source-name source :path key :key key))
  value)

(defun %validate-override (key value)
  (let ((valid (case key
                 ("display_wait" (or (eq value t) (null value)))
                 ("clipping" (member value '("clip" "wrap") :test #'string=))
                 ("shift_source" (member value '("vx" "vy") :test #'string=))
                 ("bnnn_register" (member value '("v0" "vx") :test #'string=))
                 ("fx0a_completion" (member value '("press" "release") :test #'string=))
                 ("memory_i" (member value '("preserve" "increment") :test #'string=))
                 ("vf_reset" (member value '("preserve" "reset") :test #'string=))
                 (otherwise t))))
    (unless valid
      (%config-error "invalid value" :path (format nil "chip8.~A" key) :key key))))

(defun %validate-toml (table source-name)
  (unless (hash-table-p table)
    (%config-error "TOML document is not a table" :source-name source-name))
  (%validate-keys table '("chip8" "logging") source-name nil)
  (dolist (section '("chip8" "logging"))
    (multiple-value-bind (value presentp) (%hash-value table section)
      (when presentp
        (unless (hash-table-p value)
          (%config-error "section must be a table" :source-name source-name :path section))
        (%validate-keys value
                        (if (string= section "chip8")
                            (mapcar #'car (cdr (assoc section +chip8-config-schema+ :test #'string=)))
                            '("path"))
                        source-name section))))
  table)

(defun %parse-toml-file (pathname)
  (handler-case
      (let ((table (cl-toml-kit:parse-file pathname)))
        (%validate-toml table (namestring pathname)))
    (cl-toml-kit:toml-parse-error (condition)
      (error 'chip8-config-error
             :source-name (cl-toml-kit:toml-parse-error-source-name condition)
             :line (cl-toml-kit:toml-parse-error-line condition)
             :column (cl-toml-kit:toml-parse-error-column condition)
             :path (cl-toml-kit:toml-parse-error-path condition)
             :reason (cl-toml-kit:toml-parse-error-expected condition)))))

(defun %profile-quirks (profile overrides)
  (let ((constructor (find-symbol "MAKE-CHIP8-QUIRKS" :cl-chip8)))
    (if (and constructor (fboundp constructor))
        (flet ((kw (name)
                 (and name (intern (string-upcase name) :keyword))))
          (let ((display-wait (getf overrides :DISPLAY_WAIT :absent)))
            (funcall constructor
                   :profile (kw profile)
                   :display-wait (unless (eq display-wait :absent)
                                   (if display-wait :wait :none))
                   :clipping (kw (getf overrides :CLIPPING))
                   :shift-source (kw (getf overrides :SHIFT_SOURCE))
                   :bnnn-register (kw (getf overrides :BNNN_REGISTER))
                   :fx0a-completion (kw (getf overrides :FX0A_COMPLETION))
                   :memory-i (kw (getf overrides :MEMORY_I))
                   :vf-behavior (kw (getf overrides :VF_RESET)))))
        (list :profile profile :overrides overrides))))

(defun merge-chip8-config (&key defaults toml cli source-name)
  "Merge profile defaults, TOML values, and explicit CLI values."
  (%validate-keys defaults '("rom" "clock_hz" "quirks") "defaults" nil)
  (%validate-keys cli '("rom" "clock_hz" "quirks" "log") "cli" nil)
  (let* ((toml-chip8 (and (hash-table-p toml) (gethash "chip8" toml)))
         (toml-logging (and (hash-table-p toml) (gethash "logging" toml)))
         (profile (or (%value (list defaults toml-chip8 cli) "quirks") "modern"))
         (clock (or (%value (list defaults toml-chip8 cli) "clock_hz")
                    +default-chip8-clock-hz+))
         (log-path (%value (list defaults toml-logging cli) "log"))
         (rom-path (%value (list defaults toml cli) "rom"))
         (overrides nil))
    (%require-type profile (lambda (x) (member x '("modern" "cosmac-vip") :test #'string=))
                   "profile must be modern or cosmac-vip" "chip8.quirks" (or source-name "configuration"))
    (%require-type clock (lambda (x) (and (integerp x) (>= x 1)))
                   "expected a positive integer" "chip8.clock_hz" (or source-name "configuration"))
    (dolist (key '("display_wait" "clipping" "shift_source" "bnnn_register"
                   "fx0a_completion" "memory_i" "vf_reset"))
      (multiple-value-bind (value presentp) (%source-value toml-chip8 key)
        (when presentp
      (%validate-override key value)
          (setf (getf overrides (intern (string-upcase key) :keyword)) value))))
    (when log-path (%require-type log-path #'stringp "expected a string" "logging.path"
                                  (or source-name "configuration")))
    (%make-chip8-config :rom-path rom-path :clock-hz clock
                        :quirks (%profile-quirks profile overrides)
                        :log-path log-path)))

(defun load-chip8-config-file (pathname &key defaults cli)
  (merge-chip8-config :defaults defaults :toml (%parse-toml-file pathname) :cli cli
                      :source-name (namestring pathname)))

(defun make-chip8-config-from-sources (&key defaults toml-path cli)
  (merge-chip8-config :defaults defaults
                      :toml (when toml-path (%parse-toml-file toml-path)) :cli cli
                      :source-name (and toml-path (namestring toml-path))))
