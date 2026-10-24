
  (require :asdf)
  (asdf:load-system "cl-json-kit")
  (defparameter +platform-id-keywords+
    '(("originalChip8" . :original-chip8)
      ("hybridVIP" . :hybrid-vip)
      ("modernChip8" . :modern-chip8)
      ("chip8x" . :chip8x)
      ("chip48" . :chip48)
      ("superchip1" . :superchip1)
      ("superchip" . :superchip)
      ("megachip8" . :megachip8)
      ("xochip" . :xochip)))
  (defparameter +quirk-id-keywords+
    '(("shift" . :shift)
      ("memoryIncrementByX" . :memory-increment-by-x)
      ("memoryLeaveIUnchanged" . :memory-leave-i-unchanged)
      ("wrap" . :wrap)
      ("jump" . :jump)
      ("vblank" . :vblank)
      ("logic" . :logic)))
  (defun expect-object (value context)
    (unless (hash-table-p value)
      (error "~A must be a JSON object." context))
    value)
  (defun expect-array (value context)
    (unless (and (vectorp value) (not (stringp value)))
      (error "~A must be a JSON array." context))
    value)
  (defun expect-string (value context)
    (unless (stringp value)
      (error "~A must be a JSON string." context))
    value)
  (defun required-field (object key context)
    (expect-object object context)
    (multiple-value-bind (value present-p) (gethash key object)
      (unless present-p
        (error "~A is missing required field ~A." context key))
      value))
  (defun optional-field (object key context)
    (expect-object object context)
    (gethash key object))
  (defun sorted-object-keys (object context)
    (expect-object object context)
    (let ((keys nil))
      (maphash
       (lambda (key value)
         (declare (ignore value))
         (unless (stringp key)
           (error "~A contains a non-string JSON object key." context))
         (push key keys))
       object)
      (sort keys #'string<)))
  (defun validate-known-keys (object allowed context)
    (dolist (key (sorted-object-keys object context))
      (unless (member key allowed :test #'string=)
        (error "~A contains unexpected field ~A." context key)))
    object)
  (defun id-keyword (id mapping context)
    (or (cdr (assoc id mapping :test #'string=))
        (error "~A contains unknown ID ~A." context id)))
  (defun validate-id-catalog (value mapping context)
    (let* ((entries (expect-array value context))
           (expected-ids (mapcar #'car mapping)))
      (unless (= (length entries) (length expected-ids))
        (error "~A must contain ~D IDs; found ~D."
               context (length expected-ids) (length entries)))
      (loop for entry across entries
            for expected-id in expected-ids
            for index from 0
            for entry-context = (format nil "~A entry ~D" context index)
            for id = (expect-string
                      (required-field entry "id" entry-context)
                      (format nil "~A.id" entry-context))
            unless (string= id expected-id)
              do (error "~A has ID ~A at index ~D; expected ~A."
                        context id index expected-id))
      t))
  (defun sha1-string-p (value)
    (and (stringp value)
         (= (length value) 40)
         (every
          (lambda (character)
            (or (char<= #\0 character #\9)
                (char<= #\a character #\f)
                (char<= #\A character #\F)))
          value)))
  (defun canonical-sha1-p (value)
    (and (sha1-string-p value)
         (string= value (string-downcase value))))
  (defun parse-generator-arguments ()
    (let ((arguments (uiop:command-line-arguments))
          (input-directory nil)
          (output-path nil)
          (source-revision nil))
      (when (and arguments (string= (first arguments) "--"))
        (pop arguments))
      (loop while arguments
            for option = (pop arguments)
            do (unless arguments
                 (error "Option ~A requires a value." option))
               (let ((value (pop arguments)))
                 (when (string= value "")
                   (error "Option ~A requires a non-empty value." option))
                 (cond
                   ((string= option "--input-dir")
                    (when input-directory
                      (error "Option --input-dir may appear only once."))
                    (setf input-directory value))
                   ((string= option "--output")
                    (when output-path
                      (error "Option --output may appear only once."))
                    (setf output-path value))
                   ((string= option "--source-revision")
                    (when source-revision
                      (error "Option --source-revision may appear only once."))
                    (setf source-revision value))
                   (t
                    (error "Unknown option ~A." option)))))
      (unless (and input-directory output-path source-revision)
        (error "Usage: --input-dir DIR --output FILE --source-revision REVISION"))
      (unless (sha1-string-p source-revision)
        (error "--source-revision must be a 40-character hexadecimal revision."))
      (values (uiop:ensure-directory-pathname input-directory)
              (pathname output-path)
              (string-downcase source-revision))))
  (defun read-json-file (path)
    (with-open-file (stream path
                            :direction :input
                            :external-format :utf-8)
      (json-kit:read-json stream :duplicate-key-policy :error)))
  (defun platform-keywords (value context)
    (loop for raw-id across (expect-array value context)
          for id = (expect-string raw-id context)
          collect (id-keyword id +platform-id-keywords+ context)))
  (defun platform-default-tickrates (value context)
    (let ((entries (expect-array value context)))
      (unless (plusp (length entries))
        (error "~A must not be empty." context))
      (loop for entry across entries
            for index from 0
            for entry-context = (format nil "~A entry ~D" context index)
            for id = (expect-string
                      (required-field entry "id" entry-context)
                      (format nil "~A.id" entry-context))
            for tickrate = (required-field entry "defaultTickrate" entry-context)
            do (unless (and (realp tickrate) (> tickrate 0))
                 (error "~A.defaultTickrate must be a positive JSON number."
                        entry-context))
            collect (cons (id-keyword id +platform-id-keywords+ context)
                          tickrate))))
  (defun quirk-overrides-plist (value context)
    (let ((overrides (expect-object value context)))
      (validate-known-keys
       overrides (mapcar #'car +quirk-id-keywords+) context)
      (loop for (id . keyword) in +quirk-id-keywords+
            append
              (multiple-value-bind (raw-value present-p)
                  (gethash id overrides)
                (when present-p
                  (list
                   keyword
                   (cond
                     ((eq raw-value t) t)
                     ((json-kit:json-false-p raw-value) nil)
                     (t
                      (error "~A.~A must be a JSON boolean." context id)))))))))
  (defun quirky-platforms-plist (value context)
    (let ((platforms (expect-object value context)))
      (validate-known-keys
       platforms (mapcar #'car +platform-id-keywords+) context)
      (loop for (id . keyword) in +platform-id-keywords+
            append
              (multiple-value-bind (overrides present-p)
                  (gethash id platforms)
                (when present-p
                  (list
                   keyword
                   (quirk-overrides-plist
                    overrides (format nil "~A.~A" context id))))))))
  (defun colors-plist (value context)
    (let ((colors (expect-object value context)))
      (validate-known-keys colors '("pixels" "buzzer" "silence") context)
      (let ((pixels
              (loop for pixel across
                      (expect-array
                       (required-field colors "pixels" context)
                       (format nil "~A.pixels" context))
                    collect (expect-string pixel (format nil "~A.pixels" context)))))
        (append
         (list :pixels pixels)
         (multiple-value-bind (buzzer present-p)
             (optional-field colors "buzzer" context)
           (when present-p
             (list :buzzer (expect-string buzzer (format nil "~A.buzzer" context)))))
         (multiple-value-bind (silence present-p)
             (optional-field colors "silence" context)
           (when present-p
             (list :silence
                   (expect-string silence (format nil "~A.silence" context)))))))))
  (defun rom-record-plist (program rom context)
    (let* ((program-object (expect-object program context))
           (rom-object (expect-object rom context))
           (title
             (expect-string
              (required-field program-object "title" context)
              (format nil "~A.title" context)))
           (platforms
             (platform-keywords
              (required-field rom-object "platforms" context)
              (format nil "~A.platforms" context))))
      (append
       (list :title title :platforms platforms)
       (multiple-value-bind (value present-p)
           (optional-field rom-object "quirkyPlatforms" context)
         (when present-p
           (list :quirky-platforms
                 (quirky-platforms-plist
                  value (format nil "~A.quirkyPlatforms" context)))))
       (multiple-value-bind (value present-p)
           (optional-field rom-object "tickrate" context)
         (when present-p
           (unless (realp value)
             (error "~A.tickrate must be a JSON number." context))
           (list :tickrate value)))
       (multiple-value-bind (value present-p)
           (optional-field rom-object "colors" context)
         (when present-p
           (list :colors
                 (colors-plist value (format nil "~A.colors" context)))))
       (multiple-value-bind (value present-p)
           (optional-field rom-object "screenRotation" context)
         (when present-p
           (unless (realp value)
             (error "~A.screenRotation must be a JSON number." context))
           (list :screen-rotation value)))
       (multiple-value-bind (value present-p)
           (optional-field rom-object "fontStyle" context)
         (when present-p
           (list :font-style
                 (expect-string value (format nil "~A.fontStyle" context)))))
       (multiple-value-bind (value present-p)
           (optional-field rom-object "startAddress" context)
         (when present-p
           (unless (or (realp value) (stringp value))
             (error "~A.startAddress must be a JSON number or string." context))
           (list :start-address value))))))
  (defun collect-rom-records (programs mapping)
    (let* ((program-array (expect-array programs "database/programs.json"))
           (sha1-object (expect-object mapping "database/sha1-hashes.json"))
           (nested-sha1s nil))
      (unless (= (length program-array) 484)
        (error "database/programs.json must contain 484 programs; found ~D."
               (length program-array)))
      (unless (= (hash-table-count sha1-object) 543)
        (error "database/sha1-hashes.json must contain 543 hashes; found ~D."
               (hash-table-count sha1-object)))
      (loop for program across program-array
            for index from 0
            for context = (format nil "database/programs.json entry ~D" index)
            do (expect-object program context)
               (expect-string
                (required-field program "title" context)
                (format nil "~A.title" context))
               (let ((roms
                       (expect-object
                        (required-field program "roms" context)
                        (format nil "~A.roms" context))))
                 (dolist (sha1 (sorted-object-keys roms context))
                   (unless (canonical-sha1-p sha1)
                     (error "~A.roms contains a non-canonical SHA1 key ~A."
                            context sha1))
                   (when (member sha1 nested-sha1s :test #'string=)
                     (error "SHA1 ~A appears in more than one program." sha1))
                   (push sha1 nested-sha1s))))
      (unless (= (length nested-sha1s) 543)
        (error "The program ROM objects must contain 543 SHA1 keys; found ~D."
               (length nested-sha1s)))
      (let ((mapping-keys (sorted-object-keys sha1-object "database/sha1-hashes.json"))
            (nested-keys (sort nested-sha1s #'string<)))
        (unless (equal mapping-keys nested-keys)
          (error "SHA1 mapping keys do not match programs.json ROM keys."))
        (loop for sha1 in mapping-keys
              collect
                (let ((index (required-field
                              sha1-object sha1 "database/sha1-hashes.json")))
                  (unless (and (integerp index)
                               (<= 0 index)
                               (< index (length program-array)))
                    (error "SHA1 ~A maps to invalid program index ~S."
                           sha1 index))
                  (let* ((program (aref program-array index))
                         (roms
                           (expect-object
                            (required-field program "roms"
                                            (format nil "program index ~D" index))
                            (format nil "program index ~D.roms" index))))
                    (multiple-value-bind (rom present-p) (gethash sha1 roms)
                      (unless present-p
                        (error "SHA1 ~A maps to program index ~D, but is absent from that program's roms object."
                               sha1 index))
                      (cons
                       sha1
                       (rom-record-plist
                        program rom (format nil "SHA1 ~A" sha1))))))))))
  (defun write-rom-database (output-path source-revision records platform-default-tickrates)
    (with-open-file (stream output-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
      (format stream
              ";;;; Generated from chip-8/chip-8-database at revision ~A~%;;;; Copyright 2023 The CHIP-8 database authors~%~%(in-package #:cl-chip8)~%~%(defparameter *rom-database-platform-default-tickrates*~%  '"
              source-revision)
      (let ((*print-case* :downcase)
            (*print-readably* t)
            (*print-pretty* nil))
        (prin1 platform-default-tickrates stream)
        (format stream ")~%~%(defparameter *rom-database-records*~%  '(")
        (dolist (record records)
          (terpri stream)
          (write-string "    " stream)
          (prin1 record stream))
        (format stream "~%    ))~%"))))
  (defun main ()
    (multiple-value-bind (input-directory output-path source-revision)
        (parse-generator-arguments)
      (let* ((database-directory (merge-pathnames #p"database/" input-directory))
             (programs
               (read-json-file
                (merge-pathnames #p"programs.json" database-directory)))
             (sha1-hashes
               (read-json-file
                (merge-pathnames #p"sha1-hashes.json" database-directory)))
             (platforms
               (read-json-file
                (merge-pathnames #p"platforms.json" database-directory)))
             (quirks
               (read-json-file
                (merge-pathnames #p"quirks.json" database-directory))))
        (validate-id-catalog platforms +platform-id-keywords+
                             "database/platforms.json")
        (validate-id-catalog quirks +quirk-id-keywords+
                             "database/quirks.json")
        (let ((platform-default-tickrates
                (platform-default-tickrates platforms "database/platforms.json")))
          (let ((records (collect-rom-records programs sha1-hashes)))
            (write-rom-database output-path source-revision records
                                platform-default-tickrates)
            (format t "Generated ~D ROM records in ~A.~%"
                    (length records) (namestring output-path)))))))
  (in-package #:cl-user)
  (main)
