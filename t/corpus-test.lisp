;;;; ROM corpus smoke tests. The corpus is supplied through
;;;; CL_CHIP8_ROM_CORPUS; no ROM bytes are vendored here.
;;;;
;;;; Without the environment variable, the corpus and golden specs report a
;;;; skip. Other specs use synthetic ROMs to test discovery and fault handling.
(in-package #:cl-chip8/test)

;;; ---------------------------------------------------------------------------
;;; Configuration
;;; ---------------------------------------------------------------------------

(defparameter *rom-corpus-root-variable* "CL_CHIP8_ROM_CORPUS"
  "Name of the environment variable holding a ROM corpus root.
When it is unset or blank, the corpus spec skips.")

(defparameter *rom-corpus-frame-count* 600
  "Number of 60 Hz frames executed for every archive ROM.")

(defparameter *temp-corpus-counter* 0
  "Process-local counter for temporary corpus directory names.")

(defparameter *temp-corpus-counter-lock* (sb-thread:make-mutex)
  "Lock protecting the temporary corpus directory counter.")

(defparameter *rom-corpus-outcome-order*
  '(:completed
    :not-a-rom
    :unsupported-platform
    :unsupported-opcode
    :too-large
    :memory-access-out-of-bounds
    :stack-overflow
    :stack-underflow
    :blank-frame
    :error)
  "Every outcome %RUN-CORPUS-ROM can return, in summary-report order.")

(defparameter *rom-corpus-fault-outcomes*
  '(:unsupported-opcode
    :too-large
    :memory-access-out-of-bounds
    :stack-overflow
    :stack-underflow
    :blank-frame
    :error)
  "Outcomes that fail the corpus spec. Unsupported platforms are reported as per-ROM exclusions under FR-011.")

(defun %corpus-environment-value (name)
  "Return environment variable NAME's value with surrounding blanks trimmed, or
NIL when it is unset or blank. Treating a blank value as unset means
`CL_CHIP8_ROM_CORPUS=` skips rather than failing on an empty corpus root."
  (let ((value (host-kit:getenv name)))
    (when value
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
        (when (plusp (length trimmed))
          trimmed)))))

(defun %corpus-root ()
  "Return the configured corpus root as a directory pathname, or NIL when
*ROM-CORPUS-ROOT-VARIABLE* is unset."
  (let ((configured (%corpus-environment-value *rom-corpus-root-variable*)))
    (when configured
      (host-kit:ensure-directory-pathname (host-kit:ensure-pathname configured)))))

;;; ---------------------------------------------------------------------------
;;; ROM discovery
;;; ---------------------------------------------------------------------------

(defun %corpus-rom-file-p (pathname metadata)
  "True when PATHNAME/METADATA denote a regular file typed .ch8, case-blind.
Symbolic links are excluded by HOST-KIT:CALL-WITH-DIRECTORY-TREE's default of
not following them, so a link farm cannot make one ROM appear several times."
  (and (eq (host-kit:file-metadata-kind metadata) :regular-file)
       (stringp (pathname-type pathname))
       (string-equal (pathname-type pathname) "ch8")))

(defun %corpus-rom-files (root)
  "Return every .ch8 regular file under ROOT, depth-first, in lexical order.
chip8Archive stores its ROMs one directory below the root it is usually cloned
to, so this descends rather than listing ROOT's direct entries."
  (let ((files '()))
    (host-kit:call-with-directory-tree
     (lambda (pathname metadata depth)
       (declare (ignore depth))
       (when (%corpus-rom-file-p pathname metadata)
         (push pathname files)))
     root)
    (nreverse files)))

;;; ---------------------------------------------------------------------------
;;; Running one ROM
;;; ---------------------------------------------------------------------------

(defun %run-corpus-rom (path frame-count &key rom-record platform)
  "Run PATH for FRAME-COUNT 60 Hz frames using the resolved ROM configuration.

Returns (VALUES OUTCOME CONDITION FRAME CONFIG). OUTCOME is :COMPLETED when
the final framebuffer contains a lit pixel, :BLANK-FRAME when it does not,
:NOT-A-ROM for the known Octo source path stored with a .ch8 suffix, or a
classified loading/execution outcome. CONFIG is the profile and clock rate used
for the run. A key wait leaves the machine waiting while timers continue to
advance; a halted machine advances timers for the remaining frames."
  (check-type frame-count (integer 1 *))
  (handler-case
      (let ((bytes (cl-chip8::%read-rom-file path)))
        (if (and
                 (equalp (last (pathname-directory path) 2)
                         (quote ("src" "BadKaiJuJu")))
                 (string-equal (file-namestring path) "BadKaiJuJu.ch8")
                 (>= (length bytes) 6)
                 (equalp (subseq bytes 0 6)
                         #(#x3A #x61 #x6C #x69 #x61 #x73)))
            (values :not-a-rom
                    "matches the Octo source at src/BadKaiJuJu/BadKaiJuJu.ch8"
                    nil nil)
            (let* (;; Keep ROM random opcodes independent of prior test ordering.
                   (*random-state* (sb-ext:seed-random-state 600))
                   (record (or rom-record (find-rom-record bytes)))
                   (platform-override
                     (when platform
                       (list :platform
                             (if (stringp platform)
                                 platform
                                 (string-downcase (symbol-name platform))))))
                   (config (make-chip8-config-from-sources
                            :cli platform-override
                            :rom-record record))
                   (resolved-platform (chip8-config-platform config))
                   (machine (make-chip8-machine
                             :platform resolved-platform
                             :quirks (chip8-config-quirks config)
                             :memory-size
                             (if record
                                 (chip8-platform-memory-size resolved-platform)
                                 +maximum-memory-size+)))
                   (remainder 0)
                   (halted-p nil))
              (load-rom machine bytes)
              (loop repeat frame-count
                    do (multiple-value-bind (instructions next-remainder)
                           (floor (+ remainder (chip8-config-clock-hz config)) 60)
                         (setf remainder next-remainder)
                         (if halted-p
                             (step-timers! machine)
                             (let ((result
                                     (chip8-run-ticks
                                      machine 1
                                      :instructions-per-tick instructions)))
                               (when (eq (chip8-run-result-status result) :halted)
                                 (setf halted-p t))))))
              (let ((frame (chip8-framebuffer-snapshot machine)))
                (if (loop for index below (array-total-size frame)
                          thereis (plusp (row-major-aref frame index)))
                    (values :completed nil frame config)
                    (values :blank-frame
                            (format nil "frame ~D is completely blank" frame-count)
                            frame config))))))
    (chip8-unsupported-platform (condition)
      (values :unsupported-platform condition nil nil))
    (chip8-rom-too-large (condition)
      (values :too-large condition nil nil))
    (chip8-invalid-opcode (condition)
      (values :unsupported-opcode condition nil nil))
    (chip8-memory-access-out-of-bounds (condition)
      (values :memory-access-out-of-bounds condition nil nil))
    (chip8-stack-overflow (condition)
      (values :stack-overflow condition nil nil))
    (chip8-stack-underflow (condition)
      (values :stack-underflow condition nil nil))
    (error (condition)
      (values :error condition nil nil))))

(defun %corpus-outcomes (roms frame-count)
  "Run every ROM in ROMS for FRAME-COUNT 60 Hz frames.
Return (PATHNAME OUTCOME CONDITION) entries in ROMS order."
  (loop for rom in roms
        collect (multiple-value-bind (outcome condition)
                    (%run-corpus-rom rom frame-count)
                  (list rom outcome condition))))

(defun %printable-corpus-name (path)
  "Return the filename of PATH with control characters replaced by a period.

This keeps terminal reports from being rewritten by escape sequences.
Replacements use one visible character per input control character."
  (map 'string
       (lambda (character)
         (if (or (char< character #\Space) (char= character (code-char 127)))
             #\.
             character))
       (file-namestring path)))
(defun %framebuffer-ascii (framebuffer)
  "Return FRAMEBUFFER as rows of ASCII pixels for golden review."
  (with-output-to-string (stream)
    (loop for y below (array-dimension framebuffer 0)
          do (loop for x below (array-dimension framebuffer 1)
                   for pixel = (aref framebuffer y x)
                   do (write-char (case pixel
                                    (0 #\.)
                                    (1 #\#)
                                    (2 #\+)
                                    (3 #\@)
                                    (otherwise #\?))
                                  stream))
             (unless (= y (1- (array-dimension framebuffer 0)))
               (terpri stream)))))
(defun %corpus-golden-ascii (root relative-path expected-platform
                             &optional override-platform)
  "Run one archive ROM for 600 frames and return its ASCII framebuffer."
  (let ((path (find relative-path
                    (%corpus-rom-files root)
                    :key (lambda (pathname)
                           (enough-namestring pathname root))
                    :test #'string=)))
    (unless path
      (error "Golden ROM ~A was not found under ~A." relative-path root))
    (multiple-value-bind (outcome condition frame config)
        (%run-corpus-rom path *rom-corpus-frame-count*
                         :platform override-platform)
      (unless (eq outcome :completed)
        (error "Golden ROM ~A under ~A ended as ~(~A~): ~A"
               relative-path expected-platform outcome condition))
      (let ((actual-platform
              (chip8-platform-name (chip8-config-platform config))))
        (unless (eq actual-platform expected-platform)
          (error "Golden ROM ~A resolved to ~A instead of ~A."
                 relative-path actual-platform expected-platform)))
      (%framebuffer-ascii frame))))

(defun %corpus-faults (outcomes)
  "Return one report string per entry of OUTCOMES whose outcome is a fault.
Each string names the ROM, its outcome class, and the condition or reason."
  (loop for entry in outcomes
        for path = (first entry)
        for outcome = (second entry)
        for condition = (third entry)
        when (member outcome *rom-corpus-fault-outcomes*)
          collect (format nil "~A: ~(~A~): ~A"
                          (%printable-corpus-name path)
                          outcome
                          condition)))

(defun %corpus-tally (outcomes)
  "Return an alist of (OUTCOME . COUNT) entries in the configured report order,
including classes with zero results."
  (loop for class in *rom-corpus-outcome-order*
        collect (cons class
                      (count class outcomes :key #'second))))

(defun %report-corpus-summary (root frame-count outcomes stream)
  "Write outcome counts and each per-ROM exclusion with its reason."
  (format stream "~&;; cl-chip8 ROM corpus smoke test~%")
  (format stream ";;   corpus root : ~A~%" root)
  (format stream ";;   frames      : ~D at 60 Hz per ROM~%" frame-count)
  (loop for (class . count) in (%corpus-tally outcomes)
        do (format stream ";;   ~(~30A~): ~D~%" class count))
  (format stream ";;   ~30A: ~D~%" "total" (length outcomes))
  (loop for entry in outcomes
        for path = (first entry)
        for outcome = (second entry)
        for reason = (third entry)
        do (case outcome
             (:unsupported-platform
              (format stream
                      ";;   excluded ROM ~A: unsupported platform ~A (FR-011)~%"
                      (%printable-corpus-name path)
                      (chip8-unsupported-platform-name reason)))
             (:not-a-rom
              (format stream ";;   excluded non-ROM file ~A: ~A~%"
                      (%printable-corpus-name path)
                      reason))))
  (values))

;;; ---------------------------------------------------------------------------
;;; Synthetic ROMs, for the self-tests below
;;; ---------------------------------------------------------------------------

(defun %corpus-bytes (&rest bytes)
  (make-array (length bytes) :element-type '(unsigned-byte 8) :initial-contents bytes))

(defun %looping-rom-bytes ()
  "Draw one pixel at the origin, then loop and redraw it every frame."
  (%corpus-bytes
   #xA2 #x0A
   #x60 #x00
   #x61 #x00
   #xD0 #x11
   #x12 #x08
   #x80))

(defun %unsupported-opcode-rom-bytes ()
  "5F01 is invalid because family 5 supports only 5XY0, 5XY2, and 5XY3."
  (%corpus-bytes #x5F #x01))

(defun %out-of-bounds-rom-bytes ()
  "F000 FFFF sets I to 0xFFFF, then F165 loads V0..V1 from [I]. On the
:XO-CHIP platform the two-byte register load crosses the 64KB memory limit, so
CHECK-MEMORY-ACCESS signals CHIP8-MEMORY-ACCESS-OUT-OF-BOUNDS."
  (%corpus-bytes #xF0 #x00 #xFF #xFF #xF1 #x65))

(defun %stack-underflow-rom-bytes ()
  "00EE: RET with an empty call stack."
  (%corpus-bytes #x00 #xEE))

(defun %stack-overflow-rom-bytes ()
  "2200: CALL 0x200 -- call the address the instruction itself sits at, so each
call re-executes it and pushes another return address. The 17th push exceeds
the 16-level call stack and signals CHIP8-STACK-OVERFLOW."
  (%corpus-bytes #x22 #x00))

(defun %oversized-rom-bytes ()
  "One byte beyond the remaining 64-KiB memory after the ROM load address."
  (make-array (1+ (- +maximum-memory-size+ +rom-load-address+))
              :element-type '(unsigned-byte 8)
              :initial-element 0))

;;; ---------------------------------------------------------------------------
;;; Temporary corpus trees
;;; ---------------------------------------------------------------------------

(defun %write-corpus-rom (root name bytes)
  "Write BYTES to NAME under ROOT and return the pathname.
NAME may name a subdirectory, which is created. This SBCL-only test uses /tmp
to avoid dependence on an external temporary-file API."
  (let ((path (merge-pathnames name (host-kit:ensure-directory-pathname root))))
    (ensure-directories-exist path)
    (with-open-file (stream path :direction :output :if-exists :supersede
                                 :element-type '(unsigned-byte 8))
      (write-sequence bytes stream))
    path))

(defun %call-with-temp-corpus (thunk)
  "Create a fresh temporary corpus directory, call THUNK with it, delete it."
  (let ((root (merge-pathnames
               (format nil "cl-chip8-corpus-test-~D/"
                       (sb-thread:with-mutex (*temp-corpus-counter-lock*)
                         (incf *temp-corpus-counter*)))
               #p"/tmp/")))
    (unwind-protect
         (progn
           (host-kit:ensure-directory-tree root)
           (funcall thunk root))
      (host-kit:delete-directory-tree root :if-does-not-exist :ignore))))

(defmacro with-temp-corpus ((root-var) &body body)
  `(%call-with-temp-corpus (lambda (,root-var) ,@body)))

;;; ---------------------------------------------------------------------------
;;; The corpus spec itself
;;; ---------------------------------------------------------------------------

(describe "chip8Archive ROM corpus compatibility"
  (it "runs every .ch8 ROM for 600 frames without faults or a blank final frame"
    (let ((root (%corpus-root)))
      (unless root
        (skip (format nil "~A is unset. Set it to a directory tree of .ch8 files ~
                           (for example a clone of JohnEarnest/chip8Archive) to run ~
                           the corpus compatibility test."
                      *rom-corpus-root-variable*)))
      (unless (host-kit:directory-exists-p root)
        (error "~A names ~A, which is not an existing directory."
               *rom-corpus-root-variable* root))
      (let ((roms (%corpus-rom-files root)))
        (expect (length roms) :to-be-greater-than 0)
        (let ((outcomes (%corpus-outcomes roms *rom-corpus-frame-count*)))
          (%report-corpus-summary root *rom-corpus-frame-count* outcomes
                                  *standard-output*)
          (expect (%corpus-faults outcomes) :to-equal '()))))))

;;; ---------------------------------------------------------------------------
;;; Self-tests: these need no corpus and run on every invocation
;;; ---------------------------------------------------------------------------

(describe "ROM corpus frame count"
  (it "uses the required 600-frame run"
    (expect *rom-corpus-frame-count* :to-be 600)))

(describe "ROM corpus discovery"
  (it "finds .ch8 files in the root and in nested subdirectories"
    (with-temp-corpus (root)
      (%write-corpus-rom root "top.ch8" (%looping-rom-bytes))
      (%write-corpus-rom root "nested/deeper/inner.ch8" (%looping-rom-bytes))
      ;; Depth-first, siblings in lexical order: "nested" is descended before
      ;; "top.ch8" is reached, so the nested ROM comes first.
      (expect (mapcar #'file-namestring (%corpus-rom-files root))
              :to-equal '("inner.ch8" "top.ch8"))))
  (it "ignores files that are not typed .ch8"
    (with-temp-corpus (root)
      (%write-corpus-rom root "keep.ch8" (%looping-rom-bytes))
      (%write-corpus-rom root "README.md" (%corpus-bytes #x23))
      (%write-corpus-rom root "notes.txt" (%corpus-bytes #x23))
      (expect (mapcar #'file-namestring (%corpus-rom-files root))
              :to-equal '("keep.ch8"))))
  (it "matches the .CH8 type case-blind"
    (with-temp-corpus (root)
      (%write-corpus-rom root "shouty.CH8" (%looping-rom-bytes))
      (expect (length (%corpus-rom-files root)) :to-be 1)))
  (it "returns an empty list for a corpus directory holding no ROM"
    (with-temp-corpus (root)
      (expect (%corpus-rom-files root) :to-equal '()))))

(describe "ROM corpus fault-report sanitisation"
  ;; These tests call the formatter directly because control characters in
  ;; real filenames are awkward to create portably; the property belongs to
  ;; formatting, not discovery.
  (it "replaces an escape sequence in a ROM name so it cannot rewrite the report"
    (let ((sanitised (%printable-corpus-name
                      (make-pathname :name (format nil "evil~C[2K" (code-char 27))
                                     :type "ch8"))))
      (with-soft-assertions
        (expect (find (code-char 27) sanitised) :to-be nil)
        (expect (search "evil" sanitised) :to-be 0))))
  (it "replaces a control character with a visible marker"
    (let ((name (%printable-corpus-name
                 (make-pathname :name (format nil "rom~C" (code-char 7))
                                :type "ch8"))))
      (expect (search "rom." name) :to-be 0)))
  (it "leaves an ordinary ROM name untouched"
    (expect (%printable-corpus-name #p"/tmp/pong.ch8") :to-equal "pong.ch8")))

(describe "ROM corpus outcome classification"
  (it "excludes the known Octo source without rejecting a ROM with the same prefix"
    (with-temp-corpus (root)
      (let* ((source
               (%write-corpus-rom
                root "src/BadKaiJuJu/BadKaiJuJu.ch8"
                (%corpus-bytes #x3A #x61 #x6C #x69 #x61 #x73 #x20 #x6B)))
             (rom
               (%write-corpus-rom
                root "roms/alias-prefix.ch8"
                (%corpus-bytes
                 #x3A #x61 #x6C #x69 #x61 #x73
                 #xA2 #x1E #x60 #x00 #x61 #x00 #xD0 #x11 #x12 #x0E
                 #x00 #x00 #x00 #x00 #x00 #x00 #x00
                 #x00 #x00 #x00 #x00 #x00 #x00 #x00 #x80))))
        (multiple-value-bind (outcome reason) (%run-corpus-rom source 600)
          (expect outcome :to-be :not-a-rom)
          (expect reason :to-equal
                  "matches the Octo source at src/BadKaiJuJu/BadKaiJuJu.ch8"))
        (expect (%run-corpus-rom rom 600) :to-be :completed)
        (let* ((outcomes (%corpus-outcomes (%corpus-rom-files root) 600))
               (report (with-output-to-string (stream)
                         (%report-corpus-summary root 600 outcomes stream))))
          (expect (cdr (assoc :not-a-rom (%corpus-tally outcomes))) :to-be 1)
          (expect (cdr (assoc :completed (%corpus-tally outcomes))) :to-be 1)
          (expect (%corpus-faults outcomes) :to-equal (quote ()))
          (expect (integerp
                   (search "excluded non-ROM file BadKaiJuJu.ch8: matches the Octo source at src/BadKaiJuJu/BadKaiJuJu.ch8"
                           report))
                  :to-be t)))))
  (it "classifies invalid opcodes as faults"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "invalid.ch8"
                                    (%unsupported-opcode-rom-bytes))))
        (expect (%run-corpus-rom rom 600) :to-be :unsupported-opcode))))
  (it "classifies a ROM larger than 64-KiB memory as a fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "huge.ch8"
                                    (%oversized-rom-bytes))))
        (expect (%run-corpus-rom rom 600) :to-be :too-large))))
  (it "records an unsupported database platform as an explicit exclusion"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "unsupported-platform.ch8"
                                    (%looping-rom-bytes))))
        (expect (%run-corpus-rom
                 rom 600 :rom-record '(:platforms (:hybrid-vip)))
                :to-be :unsupported-platform))))
  (it "reports a register-block load past the end of XO-CHIP memory as a fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "oob.ch8"
                                    (%out-of-bounds-rom-bytes))))
        (expect (%run-corpus-rom rom 600 :platform :xo-chip)
                :to-be :memory-access-out-of-bounds))))
  (it "reports RET on an empty call stack as a fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "underflow.ch8"
                                    (%stack-underflow-rom-bytes))))
        (expect (%run-corpus-rom rom 600) :to-be :stack-underflow))))
  (it "reports a runaway CALL chain as a fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "overflow.ch8"
                                    (%stack-overflow-rom-bytes))))
        (expect (%run-corpus-rom rom 600) :to-be :stack-overflow)))))

(describe "ROM corpus fault reporting"
  (it "fails on invalid opcodes and oversized ROMs"
    (with-temp-corpus (root)
      (%write-corpus-rom root "draw-loop.ch8" (%looping-rom-bytes))
      (%write-corpus-rom root "invalid.ch8" (%unsupported-opcode-rom-bytes))
      (%write-corpus-rom root "huge.ch8" (%oversized-rom-bytes))
      (let ((outcomes (%corpus-outcomes (%corpus-rom-files root) 600)))
        (expect (cdr (assoc :completed (%corpus-tally outcomes))) :to-be 1)
        (expect (cdr (assoc :unsupported-opcode
                            (%corpus-tally outcomes)))
                :to-be 1)
        (expect (cdr (assoc :too-large (%corpus-tally outcomes))) :to-be 1)
        (expect (length (%corpus-faults outcomes)) :to-be 2))))
  (it "names the offending ROM and fault class"
    (with-temp-corpus (root)
      (%write-corpus-rom root "draw-loop.ch8" (%looping-rom-bytes))
      (%write-corpus-rom root "oob.ch8" (%out-of-bounds-rom-bytes))
      (let ((faults (%corpus-faults
                     (%corpus-outcomes (%corpus-rom-files root) 600))))
        (expect (length faults) :to-be 1)
        (expect (search "oob.ch8" (first faults)) :to-be 0)
        (expect (integerp (search "memory-access-out-of-bounds"
                                  (first faults)))
                :to-be t)))))
(describe "chip8Archive golden frames"
  (it-each
    (("roms/chipquarium.ch8")
     ("roms/carbon8.ch8")
     ("roms/spaceracer.ch8"))
    "matches the CHIP-8 600-frame golden for ~A in both profiles"
    (relative-path)
    (let ((root (%corpus-root)))
      (unless root
        (skip (format nil "~A is unset; golden frames require chip8Archive."
                      *rom-corpus-root-variable*)))
      (let ((vip (%corpus-golden-ascii
                  root relative-path :cosmac-vip :cosmac-vip))
            (modern (%corpus-golden-ascii
                     root relative-path :modern :modern)))
        (expect vip :to-equal modern)
        (let ((cl-weave:*snapshot-file-name* "chip8archive.snapshots"))
          (expect vip :to-match-snapshot
                  (format nil "frame-600/~A/cosmac-vip" relative-path))
          (expect modern :to-match-snapshot
                  (format nil "frame-600/~A/modern" relative-path))))))
  (it-each
    (("roms/mondrian.ch8")
     ("roms/octopeg.ch8")
     ("roms/blackrainbow.ch8"))
    "matches the DB-resolved SCHIP frame-600 golden for ~A"
    (relative-path)
    (let ((root (%corpus-root)))
      (unless root
        (skip (format nil "~A is unset; golden frames require chip8Archive."
                      *rom-corpus-root-variable*)))
      (let ((frame (%corpus-golden-ascii root relative-path :schip)))
        (let ((cl-weave:*snapshot-file-name* "chip8archive.snapshots"))
          (expect frame :to-match-snapshot
                  (format nil "frame-600/~A/schip" relative-path))))))
  (it-each
    (("roms/ordinaryidlegarden.ch8")
     ("roms/trucksimul8or.ch8")
     ("roms/anEveningToDieFor.ch8"))
    "matches the DB-resolved XO-CHIP frame-600 golden for ~A"
    (relative-path)
    (let ((root (%corpus-root)))
      (unless root
        (skip (format nil "~A is unset; golden frames require chip8Archive."
                      *rom-corpus-root-variable*)))
      (let ((frame (%corpus-golden-ascii root relative-path :xo-chip)))
        (let ((cl-weave:*snapshot-file-name* "chip8archive.snapshots"))
          (expect frame :to-match-snapshot
                  (format nil "frame-600/~A/xo-chip" relative-path)))))))
