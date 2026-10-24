;;;; ROM corpus smoke tests. The corpus is supplied through
;;;; CL_CHIP8_ROM_CORPUS; no ROM bytes are vendored here.
;;;;
;;;; Without the environment variable, the corpus spec reports a skip. The
;;;; remaining specs use synthetic ROMs to test discovery, budget parsing, and
;;;; outcome classification without requiring the external corpus.
(in-package #:cl-chip8/test)

;;; ---------------------------------------------------------------------------
;;; Configuration
;;; ---------------------------------------------------------------------------

(defparameter *rom-corpus-root-variable* "CL_CHIP8_ROM_CORPUS"
  "Name of the environment variable holding a ROM corpus root.
When it is unset or blank, the corpus spec skips.")

(defparameter *rom-corpus-budget-variable* "CL_CHIP8_ROM_CORPUS_BUDGET"
  "Name of the environment variable overriding the per-ROM instruction budget.")

(defparameter *rom-corpus-default-budget* 2000
  "Default instruction budget used by the corpus smoke test for each ROM.")

(defparameter *temp-corpus-counter* 0
  "Process-local counter for temporary corpus directory names.")

(defparameter *temp-corpus-counter-lock* (sb-thread:make-mutex)
  "Lock protecting the temporary corpus directory counter.")

(defparameter *rom-corpus-outcome-order*
  '(:completed
    :unsupported-opcode
    :too-large
    :memory-access-out-of-bounds
    :stack-overflow
    :stack-underflow
    :error)
  "Every outcome %RUN-CORPUS-ROM can return, in summary-report order.")

(defparameter *rom-corpus-fault-outcomes*
  '(:memory-access-out-of-bounds :stack-overflow :stack-underflow :error)
  "The outcomes that fail the corpus spec.

:UNSUPPORTED-OPCODE and :TOO-LARGE are deliberately absent. A chip8Archive
tree carries SUPER-CHIP and XO-CHIP programs alongside the `chip8`-class ones;
those use opcodes this interpreter does not implement, and refusing them with
CHIP8-INVALID-OPCODE is correct behaviour, not a defect. Likewise a ROM larger
than the 3584 bytes between +ROM-LOAD-ADDRESS+ and the end of the address
space is correctly refused with CHIP8-ROM-TOO-LARGE. Both are counted and
reported; neither fails the run.")

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

(defun %parse-corpus-budget (value)
  "Return a valid per-ROM instruction budget.

NIL selects the default. A zero budget executes no instructions but would still
classify each ROM as completed. Requiring the full string rejects trailing text
that PARSE-INTEGER could otherwise ignore."
  (cond
    ((null value) *rom-corpus-default-budget*)
    (t
     (multiple-value-bind (parsed end) (parse-integer value :junk-allowed t)
       (unless (and parsed (= end (length value)) (plusp parsed))
         (error "~A must be a positive decimal integer, got ~S."
                *rom-corpus-budget-variable* value))
       parsed))))

(defun %corpus-budget ()
  (%parse-corpus-budget (%corpus-environment-value *rom-corpus-budget-variable*)))

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

(defun %run-corpus-rom (path budget &key (platform :modern))
  "Run PATH on PLATFORM for BUDGET instructions.

Returns (VALUES OUTCOME CONDITION). OUTCOME is a member of
*ROM-CORPUS-OUTCOME-ORDER* and CONDITION is the condition that ended the run,
NIL when no classified condition occurred. Each ROM gets a fresh machine; only
its outcome and condition are returned.

The machine is initialized for PLATFORM, then PATH is loaded and
CHIP8-RUN-INSTRUCTIONS is called. A :COMPLETED result means no classified
condition occurred; the run can stop early if the ROM halts or enters a wait
state. No input is delivered and timers are not advanced, so a ROM that reaches
FX0A or a display wait stops there and is classified as :COMPLETED. Nothing
here asserts on pixels.

Errors raised while loading or executing that are not covered by the earlier
clauses are returned as :ERROR with their condition."
  (handler-case
      (let ((machine (make-chip8-machine :platform platform)))
        (load-rom-file machine path)
        (chip8-run-instructions machine budget)
        (values :completed nil))
    (chip8-rom-too-large (condition)
      (values :too-large condition))
    (chip8-invalid-opcode (condition)
      (values :unsupported-opcode condition))
    (chip8-memory-access-out-of-bounds (condition)
      (values :memory-access-out-of-bounds condition))
    (chip8-stack-overflow (condition)
      (values :stack-overflow condition))
    (chip8-stack-underflow (condition)
      (values :stack-underflow condition))
    (error (condition)
      (values :error condition))))

(defun %corpus-outcomes (roms budget)
  "Run every ROM in ROMS for BUDGET instructions.
Return (PATHNAME OUTCOME CONDITION) entries in ROMS order."
  (loop for rom in roms
        collect (multiple-value-bind (outcome condition) (%run-corpus-rom rom budget)
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

(defun %corpus-faults (outcomes)
  "Return one report string per entry of OUTCOMES whose outcome is a fault.
An empty list is the corpus spec's pass condition, so this is what an
assertion failure prints: each string names the ROM, its outcome class, and the
condition's own report."
  (loop for (path outcome condition) in outcomes
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

(defun %report-corpus-summary (root budget outcomes stream)
  "Write the outcome tally to STREAM with its corpus root, budget, and total."
  (format stream "~&;; cl-chip8 ROM corpus smoke test~%")
  (format stream ";;   corpus root : ~A~%" root)
  (format stream ";;   budget      : ~D instruction(s) per ROM~%" budget)
  (loop for (class . count) in (%corpus-tally outcomes)
        do (format stream ";;   ~(~30A~): ~D~%" class count))
  (format stream ";;   ~30A: ~D~%" "total" (length outcomes))
  (values))

;;; ---------------------------------------------------------------------------
;;; Synthetic ROMs, for the self-tests below
;;; ---------------------------------------------------------------------------

(defun %corpus-bytes (&rest bytes)
  (make-array (length bytes) :element-type '(unsigned-byte 8) :initial-contents bytes))

(defun %looping-rom-bytes ()
  "1200: JP 0x200 -- jump to +ROM-LOAD-ADDRESS+, where PC already is.
Executes forever without ever faulting, which is the :COMPLETED case."
  (%corpus-bytes #x12 #x00))

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
  "One byte more than the space between +ROM-LOAD-ADDRESS+ and the end of
memory, so LOAD-ROM-FILE! signals CHIP8-ROM-TOO-LARGE."
  (make-array (1+ (- +memory-size+ +rom-load-address+))
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

(describe "chip8Archive ROM corpus smoke test"
  (it "runs each .ch8 ROM under CL_CHIP8_ROM_CORPUS without a classified fault"
    (let ((root (%corpus-root)))
      (unless root
        (skip (format nil "~A is unset. Set it to a directory tree of .ch8 files ~
                           (for example a clone of JohnEarnest/chip8Archive) to run ~
                           the corpus smoke test."
                      *rom-corpus-root-variable*)))
      (unless (host-kit:directory-exists-p root)
        (error "~A names ~A, which is not an existing directory."
               *rom-corpus-root-variable* root))
      (let ((budget (%corpus-budget))
            (roms (%corpus-rom-files root)))
        (expect (length roms) :to-be-greater-than 0)
        (let ((outcomes (%corpus-outcomes roms budget)))
          (%report-corpus-summary root budget outcomes *standard-output*)
          (expect (%corpus-faults outcomes) :to-equal '()))))))

;;; ---------------------------------------------------------------------------
;;; Self-tests: these need no corpus and run on every invocation
;;; ---------------------------------------------------------------------------

(describe "ROM corpus instruction budget configuration"
  (it "defaults to 2000 instructions when the budget variable is unset"
    (expect (%parse-corpus-budget nil) :to-be 2000))
  (it "accepts a positive decimal override"
    (expect (%parse-corpus-budget "10000") :to-be 10000))
  (it "rejects a zero budget, which would execute nothing while reporting completion"
    (signals error (%parse-corpus-budget "0")))
  (it "rejects a negative budget"
    (signals error (%parse-corpus-budget "-1")))
  (it "rejects a non-numeric budget rather than falling back to the default"
    (signals error (%parse-corpus-budget "many")))
  (it "rejects a trailing-junk budget PARSE-INTEGER would otherwise read as a prefix"
    (signals error (%parse-corpus-budget "2000instructions"))))

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
  (it "reports a ROM that runs its whole budget as completed"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "loop.ch8" (%looping-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :completed))))
  (it "reports an unimplemented opcode as unsupported-opcode rather than a fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "super.ch8" (%unsupported-opcode-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :unsupported-opcode))))
  (it "reports a ROM larger than the address space as too-large rather than a fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "huge.ch8" (%oversized-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :too-large))))
  (it "reports a register-block load past the end of XO-CHIP memory as a memory fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "oob.ch8" (%out-of-bounds-rom-bytes))))
        (expect (%run-corpus-rom rom 2000 :platform :xo-chip)
                :to-be :memory-access-out-of-bounds))))
  (it "reports RET on an empty call stack as a stack fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "underflow.ch8" (%stack-underflow-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :stack-underflow))))
  (it "reports a runaway CALL chain as a stack fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "overflow.ch8" (%stack-overflow-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :stack-overflow)))))

(describe "ROM corpus fault reporting"
  (it "classifies clean, unsupported, and oversized ROMs"
    (with-temp-corpus (root)
      (%write-corpus-rom root "loop.ch8" (%looping-rom-bytes))
      (%write-corpus-rom root "super.ch8" (%unsupported-opcode-rom-bytes))
      (%write-corpus-rom root "huge.ch8" (%oversized-rom-bytes))
      (let ((outcomes (%corpus-outcomes (%corpus-rom-files root) 2000)))
        (with-soft-assertions
          (expect (%corpus-faults outcomes) :to-equal '())
          (expect (cdr (assoc :completed (%corpus-tally outcomes))) :to-be 1)
          (expect (cdr (assoc :unsupported-opcode (%corpus-tally outcomes))) :to-be 1)
          (expect (cdr (assoc :too-large (%corpus-tally outcomes))) :to-be 1)))))
  (it "names the offending ROM when one of them faults"
    (with-temp-corpus (root)
      (%write-corpus-rom root "loop.ch8" (%looping-rom-bytes))
      (%write-corpus-rom root "oob.ch8" (%out-of-bounds-rom-bytes))
      (let ((faults (%corpus-faults (%corpus-outcomes (%corpus-rom-files root) 2000))))
        (with-soft-assertions
          (expect (length faults) :to-be 1)
          (expect (search "oob.ch8" (first faults)) :to-be 0)
          (expect (integerp (search "memory-access-out-of-bounds" (first faults)))
                  :to-be t))))))
