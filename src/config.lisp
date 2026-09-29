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
   ;; Each clause is written out rather than folded into one ~@[...]~ control
   ;; string: a ~@[ clause tests the argument its own body would consume and
   ;; leaves that argument unconsumed, so a fixed five-argument control string
   ;; silently dropped the reason and shifted the key path into its place.
   (lambda (condition stream)
     (format stream "Invalid CHIP-8 configuration")
     (when (chip8-config-error-source-name condition)
       (format stream " in ~A" (chip8-config-error-source-name condition)))
     (when (chip8-config-error-line condition)
       (format stream " at ~D" (chip8-config-error-line condition))
       (when (chip8-config-error-column condition)
         (format stream ":~D" (chip8-config-error-column condition))))
     (let ((key-path (or (chip8-config-error-path condition)
                         (chip8-config-error-key condition))))
       (when key-path
         (format stream " for ~A" key-path)))
     (when (chip8-config-error-reason condition)
       (format stream "; ~A" (chip8-config-error-reason condition))))))

;; The clock default is defined before this file's merge function because ASDF
;; loads configuration before the application structure.
(defconstant +default-clock-hz+ 700)

;; Each entry is (TOML-NAME TYPE). TYPE supplies both validation and the
;; normalized value consumed by the configuration merger.
(defparameter +chip8-config-schema+
  '(("chip8" . (("quirks" . :profile) ("clock_hz" . :positive-integer)
                 ("display_wait" . :boolean) ("clipping" . (:enum "clip" "wrap"))
                 ("shift_source" . (:enum "vx" "vy"))
                 ("bnnn_register" . (:enum "v0" "vx"))
                 ("fx0a_completion" . (:enum "press" "release"))
                 ("memory_i" . (:enum "preserve" "increment"))
                 ("vf_reset" . (:enum "preserve" "reset"))))
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
      (%config-error (if source-name
                        "unknown key; cl-toml-kit does not retain source positions for valid keys"
                        "unknown key")
                     :source-name source-name
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

(defun %schema-entry (section key)
  (cdr (assoc key (cdr (assoc section +chip8-config-schema+ :test #'string=))
             :test #'string=)))

(defun %schema-keys (section)
  (mapcar #'car (cdr (assoc section +chip8-config-schema+ :test #'string=))))

(defun %schema-sections ()
  (mapcar #'car +chip8-config-schema+))

(defun %schema-value (section key value source-name)
  (let ((type (%schema-entry section key))
        (path (format nil "~A.~A" section key)))
    (unless type
      (%config-error "unknown key" :source-name source-name :path path :key key))
    (cond
      ((eq type :profile)
       (%require-type value (lambda (x) (and (stringp x)
                                             (member x '("modern" "cosmac-vip")
                                                      :test #'string=)))
                      "profile must be modern or cosmac-vip" path source-name))
      ((eq type :positive-integer)
       (%require-type value (lambda (x) (and (integerp x) (>= x 1)))
                      "expected a positive integer" path source-name))
      ((eq type :boolean)
       (%require-type value (lambda (x) (or (eq x t) (null x)))
                      "expected a boolean" path source-name))
      ((eq type :string)
       (%require-type value #'stringp "expected a string" path source-name))
      ((and (consp type) (eq (car type) :enum))
       (if (and (stringp value) (member value (cdr type) :test #'string=))
           (intern (string-upcase value) :keyword)
           (%config-error "invalid value" :source-name source-name
                          :path path :key key)))
      (t (%config-error "unsupported schema type" :source-name source-name
                        :path path :key key)))))

(defun %validate-toml (table source-name)
  (unless (hash-table-p table)
    (%config-error "TOML document is not a table" :source-name source-name))
  (%validate-keys table (%schema-sections) source-name nil)
  (dolist (section (%schema-sections))
    (multiple-value-bind (value presentp) (%hash-value table section)
      (when presentp
        (unless (hash-table-p value)
          (%config-error "section must be a table" :source-name source-name :path section))
        (%validate-keys value (%schema-keys section) source-name section))))
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
                   +default-clock-hz+))
         (log-path (or (%value (list cli) "log")
                       (%value (list toml-logging) "path")))
         (rom-path (%value (list defaults toml cli) "rom"))
         (overrides nil))
    (setf profile (%schema-value "chip8" "quirks" profile (or source-name "configuration"))
          clock (%schema-value "chip8" "clock_hz" clock (or source-name "configuration")))
    (dolist (key (remove-if (lambda (key) (member key '("quirks" "clock_hz") :test #'string=))
                            (%schema-keys "chip8")))
      (multiple-value-bind (value presentp) (%source-value toml-chip8 key)
        (when presentp
          (setf (getf overrides (intern (string-upcase key) :keyword))
                (%schema-value "chip8" key value (or source-name "configuration"))))))
    (when log-path
      (setf log-path (%schema-value "logging" "path" log-path
                                    (or source-name "configuration"))))
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
