;;;; TOML configuration and precedence rules.
(in-package #:cl-chip8)

;; The clock default is defined before this file's merge function because ASDF
;; loads configuration before the application structure.
(defconstant +default-clock-hz+ 700)
(defparameter +default-chip8-render-colors+
  '("#000000" "#00FF00" "#FFFF00" "#FFFFFF"))

;; Each entry is (TOML-NAME TYPE). TYPE supplies both validation and the
;; normalized value consumed by the configuration merger.
(defparameter +chip8-config-schema+
  '(("chip8" . (("platform" . :platform) ("quirks" . :profile)
                 ("clock_hz" . :positive-integer)
                 ("display_wait" . :display-wait)
                 ("clipping" . (:enum "clip" "wrap"))
                 ("shift_source" . (:enum "vx" "vy"))
                 ("bnnn_register" . (:enum "v0" "vx"))
                 ("fx0a_completion" . (:enum "press" "release"))
                 ("memory_i" . (:enum "preserve" "increment" "increment-x"))
                 ("vf_reset" . (:enum "preserve" "reset"))
                 ("lores_sprite" . (:enum "16x16" "8x16"))
                 ("collision" . (:enum "flag" "row-count"))
                 ("lores_scroll" . (:enum "full" "half"))
                 ("mode_switch_clear" . :boolean)))
    ("logging" . (("path" . :string)))
    ("colors" . (("pixels" . :pixel-colors)))))
;; Each entry is (DB-KEY DB-NAME PROFILE PLATFORM-OVERRIDES FALSE-MEMORY-I).
;; The mapping also names unsupported upstream platforms for diagnostics.
(defparameter +rom-database-platform-mappings+
  (quote ((:original-chip8 "originalChip8" :cosmac-vip nil :increment)
          (:modern-chip8 "modernChip8" :modern nil :increment)
          (:chip48 "chip48" :schip-legacy nil :increment-x)
          (:superchip1 "superchip1" :schip-legacy nil :increment-x)
          (:superchip "superchip" :schip nil :increment-x)
          (:xochip "xochip" :xo-chip nil :increment)
          (:hybrid-vip "hybridVIP" nil nil :increment)
          (:megachip8 "megachip8" nil nil :increment)
          (:chip8x "chip8x" nil nil :increment))))

(defstruct (chip8-config (:constructor %make-chip8-config) (:copier nil)) rom-path rom-sha1 clock-hz clock-source platform platform-source quirks quirks-source quirks-explicit-p log-path colors-pixels colors-source)

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
      ((member type '(:profile :platform) :test #'eq)
       (%require-type
        value
        (lambda (x)
          (and (stringp x)
               (member x '("modern" "cosmac-vip" "schip" "schip-legacy" "xo-chip")
                       :test #'string=)))
        (if (eq type :profile)
            "profile must be modern, cosmac-vip, schip, schip-legacy, or xo-chip"
            "platform must be modern, cosmac-vip, schip, schip-legacy, or xo-chip")
        path source-name))
      ((eq type :positive-integer)
       (%require-type value (lambda (x) (and (integerp x) (>= x 1)))
                      "expected a positive integer" path source-name))
      ((eq type :boolean)
       (%require-type value (lambda (x) (or (eq x t) (null x)))
                      "expected a boolean" path source-name))
      ((eq type :display-wait)
       (let ((validp (or (eq value t) (null value)
                         (and (stringp value) (string= value "lores-only")))))
         (unless validp
           (%config-error "expected a boolean or lores-only" :source-name source-name
                          :path path :key key))
         (if (stringp value) :lores-only value)))
      ((eq type :string)
       (%require-type value #'stringp "expected a string" path source-name))
      ((eq type :pixel-colors)
       (let* ((pixels
                (cond ((and (vectorp value) (not (stringp value)))
                       (coerce value 'list))
                      ((listp value) value)))
              (pixel-count
                (and pixels
                     (handler-case (list-length pixels)
                       (type-error () nil))))
              (trim-characters '(#\Space #\Tab #\Newline #\Return)))
         (unless (and (member pixel-count '(2 4))
                      (every
                       (lambda (color)
                         (and (stringp color)
                              (let ((color (string-trim trim-characters color)))
                                (and (= (length color) 7)
                                     (char= (char color 0) #\#)
                                     (loop for index from 1 below 7
                                           for digit = (char color index)
                                           always (or (char<= #\0 digit #\9)
                                                      (char<= #\A digit #\F)
                                                      (char<= #\a digit #\f)))))))
                       pixels))
           (%config-error "expected two or four #RRGGBB colors"
                          :source-name source-name :path path :key key))
         (mapcar (lambda (color)
                   (string-upcase (string-trim trim-characters color)))
                 pixels)))
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
  (labels ((kw (value)
             (cond ((null value) nil)
                   ((keywordp value) value)
                   (t (intern (string-upcase value) :keyword))))
           (override-value (key value)
             (cond
               ((eq key :DISPLAY_WAIT)
                (cond ((eq value :lores-only) :lores-only)
                      (value :wait)
                      (t :none)))
               ((eq key :MODE_SWITCH_CLEAR) value)
               (t (kw value)))))
    (let ((arguments (list :profile (kw profile))))
      (dolist (entry (quote ((:VF_RESET :VF-BEHAVIOR)
                             (:MEMORY_I :MEMORY-I)
                             (:DISPLAY_WAIT :DISPLAY-WAIT)
                             (:CLIPPING :CLIPPING)
                             (:SHIFT_SOURCE :SHIFT-SOURCE)
                             (:BNNN_REGISTER :BNNN-REGISTER)
                             (:FX0A_COMPLETION :FX0A-COMPLETION)
                             (:LORES_SPRITE :LORES-SPRITE)
                             (:COLLISION :COLLISION)
                             (:LORES_SCROLL :LORES-SCROLL)
                             (:MODE_SWITCH_CLEAR :MODE-SWITCH-CLEAR))))
        (multiple-value-bind (indicator value)
            (get-properties overrides (list (first entry)))
          (when indicator
            (setf arguments
                  (append arguments
                          (list (second entry)
                                (override-value (first entry) value)))))))
      (apply (function make-chip8-quirks) arguments))))
(defun resolve-chip8-clock-hz (&key cli-clock-hz toml-clock-hz
                                    db-rom-tickrate db-platform-tickrate
                                    platform-default-tickrate
                                    (fallback-clock-hz +default-clock-hz+))
  (or cli-clock-hz
      toml-clock-hz
      (when db-rom-tickrate (* 60 db-rom-tickrate))
      (when db-platform-tickrate (* 60 db-platform-tickrate))
      (when platform-default-tickrate (* 60 platform-default-tickrate))
      fallback-clock-hz))
(defun %rom-database-platform-mapping (key)
  (assoc key +rom-database-platform-mappings+ :test (function eq)))
(defun %rom-database-mapping-for-profile (mappings profile)
  (find profile mappings
        :key (function third)
        :test (function eq)))
(defun %rom-database-record-platform-mappings (record)
  (let ((keys
          (append (copy-list (getf record :platforms))
                  (loop for (key value) on (getf record :quirky-platforms)
                        by (function cddr)
                        collect key))))
    (loop with seen = nil
          with result = nil
          for key in keys
          for mapping = (%rom-database-platform-mapping key)
          do (when (and mapping
                        (not (member (first mapping) seen
                                     :test (function eq))))
               (push mapping result)
               (push (first mapping) seen))
          finally (return (nreverse result)))))
(defun %rom-database-quirk-overrides (record mapping)
  (when (and record mapping (third mapping))
    (let ((overrides nil))
      (multiple-value-bind (platform-key platform-quirks)
          (get-properties (getf record :quirky-platforms) (list (first mapping)))
        (when platform-key
          (dolist (entry (quote ((:wrap :clipping)
                                 (:shift :SHIFT_SOURCE)
                                 (:memory-leave-i-unchanged :MEMORY_I))))
            (multiple-value-bind (indicator value)
                (get-properties platform-quirks (list (first entry)))
              (when indicator
                (setf overrides
                      (append overrides
                              (list
                               (second entry)
                               (case (first entry)
                                 (:wrap (if value :wrap :clip))
                                 (:shift (if value :vx :vy))
                                 (:memory-leave-i-unchanged
                                  (if value :preserve (fifth mapping))))))))))))
      (loop for (key value) on (fourth mapping)
            by (function cddr)
            do (setf (getf overrides key) value))
      overrides)))

(defun merge-chip8-config (&key defaults toml cli source-name
                                  db-rom-tickrate db-platform-tickrate
                                  rom-record rom-sha1)
  (%validate-keys defaults (quote ("rom" "clock_hz" "quirks" "platform"))
                  "defaults" nil)
  (%validate-keys cli (quote ("rom" "clock_hz" "quirks" "platform" "log"
                              "colors_pixels"))
                  "cli" nil)
  (let* ((toml-chip8 (and (hash-table-p toml) (gethash "chip8" toml)))
         (toml-logging (and (hash-table-p toml) (gethash "logging" toml)))
         (cli-platform-p (nth-value 1 (%source-value cli "platform")))
         (cli-platform (%source-value cli "platform"))
         (toml-platform-p (nth-value 1 (%source-value toml-chip8 "platform")))
         (toml-platform (%source-value toml-chip8 "platform"))
         (defaults-platform-p (nth-value 1 (%source-value defaults "platform")))
         (defaults-platform (%source-value defaults "platform"))
         (cli-quirks-p (nth-value 1 (%source-value cli "quirks")))
         (cli-quirks (%source-value cli "quirks"))
         (toml-quirks-p (nth-value 1 (%source-value toml-chip8 "quirks")))
         (toml-quirks (%source-value toml-chip8 "quirks"))
         (defaults-quirks-p (nth-value 1 (%source-value defaults "quirks")))
         (defaults-quirks (%source-value defaults "quirks"))
         (db-platforms
           (loop for key in (getf rom-record :platforms)
                 for mapping = (%rom-database-platform-mapping key)
                 when mapping collect mapping))
         (db-record-mappings (%rom-database-record-platform-mappings rom-record))
         (db-supported (or
             (find-if (function third) db-platforms)
             (unless db-platforms
               (find-if (function third) db-record-mappings))))
         (unsupported
           (and (null db-supported)
                (if db-platforms
                    (find-if (lambda (mapping) (null (third mapping)))
                             db-platforms)
                    (find-if (lambda (mapping) (null (third mapping)))
                             db-record-mappings))))
         (unsupported-bypass
           (or cli-platform-p cli-quirks-p))
         (platform-source
           (cond (cli-platform-p :cli)
                 (toml-platform-p :toml)
                 (db-supported :db)
                 (defaults-platform-p :defaults)
                 (t :default)))
         (platform-value
           (cond (cli-platform-p cli-platform)
                 (toml-platform-p toml-platform)
                 (db-supported
                  (string-downcase (symbol-name (third db-supported))))
                 (defaults-platform-p defaults-platform)
                 (t "modern"))))
    (when (and unsupported (not unsupported-bypass))
      (error (quote chip8-unsupported-platform)
             :platform (second unsupported)))
    (setf platform-value
          (%schema-value "chip8" "platform" platform-value
                         (or source-name "configuration")))
    (let* ((profile-source
             (cond (cli-quirks-p :cli)
                   (toml-quirks-p :toml)
                   (defaults-quirks-p :defaults)
                   (t platform-source)))
           (profile-value
             (cond (cli-quirks-p cli-quirks)
                   (toml-quirks-p toml-quirks)
                   (defaults-quirks-p defaults-quirks)
                   (t platform-value)))
           (profile
             (%schema-value "chip8" "quirks" profile-value
                            (or source-name "configuration")))
           (platform-keyword (intern (string-upcase platform-value) :keyword))
           (db-quirk-mapping
             (%rom-database-mapping-for-profile db-record-mappings platform-keyword))
           (db-clock-mapping
             (or db-supported
                 (first db-platforms)
                 (first db-record-mappings)
                 (and rom-record
                      (%rom-database-mapping-for-profile
                       +rom-database-platform-mappings+ platform-keyword))))
           (db-rom-tickrate
             (or db-rom-tickrate (and rom-record (getf rom-record :tickrate))))
           (db-platform-tickrate
             (or db-platform-tickrate
                 (and rom-record db-clock-mapping
                      (rom-database-platform-default-tickrate
                       (first db-clock-mapping)))))
           (platform
             (or (find-chip8-platform platform-value)
                 (%config-error "unknown platform" :key :platform)))
           (platform-default-tickrate
             (when (member platform-source (quote (:cli :toml :defaults))
                           :test (function eq))
               (chip8-platform-default-tickrate platform)))
           (rom-path (%value (list defaults toml cli) "rom"))
           (log-path (or (%value (list cli) "log")
                         (%value (list toml-logging) "path")))
           (cli-clock-hz (%value (list cli) "clock_hz"))
           (toml-clock-hz (%value (list toml-chip8) "clock_hz"))
           (fallback-clock-hz
             (or (%value (list defaults) "clock_hz") +default-clock-hz+))
           (database-quirk-overrides
             (%rom-database-quirk-overrides rom-record db-quirk-mapping))
           (overrides (copy-list database-quirk-overrides))
           (toml-quirk-overrides-p nil)
           (colors-pixels
             (let* ((cli-colors-p
                      (nth-value 1 (%source-value cli "colors_pixels")))
                    (toml-colors-table (%source-value toml "colors"))
                    (toml-colors-p
                      (nth-value 1 (%source-value toml-colors-table "pixels")))
                    (db-colors-table (getf rom-record :colors))
                    (db-colors-p
                      (nth-value 1 (%source-value db-colors-table "pixels")))
                    (cli-colors
                      (when cli-colors-p
                        (%schema-value "colors" "pixels"
                                       (%source-value cli "colors_pixels")
                                       "command line")))
                    (toml-colors
                      (when toml-colors-p
                        (%schema-value "colors" "pixels"
                                       (%source-value toml-colors-table "pixels")
                                       (or source-name "configuration"))))
                    (db-colors
                      (when db-colors-p
                        (%schema-value "colors" "pixels"
                                       (%source-value db-colors-table "pixels")
                                       "ROM database")))
                    (default-colors
                      (copy-list +default-chip8-render-colors+)))
               (cond (cli-colors-p cli-colors)
                     (toml-colors-p toml-colors)
                     (db-colors-p db-colors)
                     (t default-colors))))
           (colors-source
             (cond ((nth-value 1 (%source-value cli "colors_pixels")) :cli)
                   ((nth-value
                     1 (%source-value (%source-value toml "colors") "pixels"))
                    :toml)
                   ((nth-value
                     1 (%source-value (getf rom-record :colors) "pixels"))
                    :db)
                   (t :default)))
           (clock nil)
           (clock-source nil))
      (setf clock
            (%schema-value
             "chip8" "clock_hz"
             (resolve-chip8-clock-hz
              :cli-clock-hz
              (and cli-clock-hz
                   (%schema-value "chip8" "clock_hz" cli-clock-hz
                                  (or source-name "configuration")))
              :toml-clock-hz
              (and toml-clock-hz
                   (%schema-value "chip8" "clock_hz" toml-clock-hz
                                  (or source-name "configuration")))
              :db-rom-tickrate db-rom-tickrate
              :db-platform-tickrate db-platform-tickrate
              :platform-default-tickrate platform-default-tickrate
              :fallback-clock-hz fallback-clock-hz)
             (or source-name "configuration"))
            clock-source
            (cond (cli-clock-hz :cli)
                  (toml-clock-hz :toml)
                  (db-rom-tickrate :db-rom)
                  (db-platform-tickrate :db-platform)
                  (platform-default-tickrate :platform-default)
                  (t :default)))
      (dolist (key
               (remove-if
                (lambda (key)
                  (member key (quote ("platform" "quirks" "clock_hz"))
                          :test (function string=)))
                (%schema-keys "chip8")))
        (multiple-value-bind (value present-p)
            (%source-value toml-chip8 key)
          (when present-p
            (setf (getf overrides (intern (string-upcase key) :keyword))
                  (%schema-value "chip8" key value
                                 (or source-name "configuration")))
            (setf toml-quirk-overrides-p t))))
      (when log-path
        (setf log-path
              (%schema-value "logging" "path" log-path
                             (or source-name "configuration"))))
      (let* ((quirks-source-tags
               (remove-duplicates
                (append (list profile-source)
                        (when database-quirk-overrides (list :db))
                        (when toml-quirk-overrides-p (list :toml)))
                :test (function eq)))
             (quirks-source
               (format nil "~{~(~A~)~^+~}"
                        (mapcar (function symbol-name) quirks-source-tags))))
        (%make-chip8-config
         :rom-path rom-path
         :rom-sha1 rom-sha1
         :clock-hz clock
         :clock-source (string-downcase (symbol-name clock-source))
         :platform platform
         :platform-source (string-downcase (symbol-name platform-source))
         :quirks (%profile-quirks profile overrides)
         :quirks-source quirks-source
         :quirks-explicit-p
         (or cli-quirks-p toml-quirks-p defaults-quirks-p overrides)
         :log-path log-path
         :colors-pixels (copy-list colors-pixels)
         :colors-source (string-downcase (symbol-name colors-source)))))))

(defun load-chip8-config-file (pathname &key defaults cli
                                         db-rom-tickrate db-platform-tickrate
                                         rom-record rom-sha1)
  (merge-chip8-config :defaults defaults :toml (%parse-toml-file pathname) :cli cli
                      :db-rom-tickrate db-rom-tickrate
                      :db-platform-tickrate db-platform-tickrate
                      :rom-record rom-record :rom-sha1 rom-sha1
                      :source-name (namestring pathname)))

(defun make-chip8-config-from-sources (&key defaults toml-path cli
                                            db-rom-tickrate db-platform-tickrate
                                            rom-record rom-sha1)
  (merge-chip8-config :defaults defaults
                      :toml (when toml-path (%parse-toml-file toml-path)) :cli cli
                      :db-rom-tickrate db-rom-tickrate
                      :db-platform-tickrate db-platform-tickrate
                      :rom-record rom-record :rom-sha1 rom-sha1
                      :source-name (and toml-path (namestring toml-path))))
