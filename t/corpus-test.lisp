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
  "Name of the environment variable holding the corpus root directory.
Unset means the corpus spec skips. See this file's header.")

(defparameter *rom-corpus-budget-variable* "CL_CHIP8_ROM_CORPUS_BUDGET"
  "Name of the environment variable overriding the per-ROM instruction budget.")

(defparameter *rom-corpus-default-budget* 2000
  "Instructions executed per ROM when the budget variable is unset.
The budget carries a typical chip8Archive program through initialization and
into its main loop, where memory bounds checks are exercised.")

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
  "Return the per-ROM instruction budget VALUE denotes.

VALUE is NIL (the variable is unset, so *ROM-CORPUS-DEFAULT-BUDGET* applies) or
a string that must parse in full as a positive decimal integer. Anything else
is an error rather than a silent fall back to the default: a budget of 0, or a
typo that PARSE-INTEGER would happily read as a prefix, would leave the corpus
spec running no instructions at all while still reporting every ROM as
completed. Split out from %CORPUS-BUDGET so it can be tested without writing to
the environment."
  (cond
    ((null value) *rom-corpus-default-budget*)
    (t
     (multiple-value-bind (parsed end) (parse-integer value :junk-allowed t)
       (unless (and parsed (= end (length value)) (plusp parsed))
         (error "~A must be a positive decimal integer, got ~S."
                *rom-corpus-budget-variable* value))
       parsed))))

(defun %corpus-budget ()
  "Return the per-ROM instruction budget from the environment."
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

(defun %run-corpus-rom (path budget)
  "Run PATH from a freshly reset machine for BUDGET instructions.

Returns (VALUES OUTCOME CONDITION): OUTCOME is a member of
*ROM-CORPUS-OUTCOME-ORDER* and CONDITION is the condition that ended the run,
NIL when the whole budget was executed. The machine is initialized with
RESET-CPU-STATE!, MEMORY-RESET!, DISPLAY-RESET!,
LOAD-FONTSET-INTO-MEMORY!, LOAD-ROM-FILE!, and KEYPAD-RESET!, then executes
instructions in a loop.

No input is delivered and no timer is advanced, so this is a CPU smoke test and
nothing here asserts on pixels. FX0A (block until a keypress) leaves PC
untouched by design, so a ROM waiting for input spins in place and consumes its
budget rather than blocking the suite.

The final ERROR clause classifies unexpected interpreter conditions as faults
instead of swallowing them. The machine retains the last ROM's state; callers
reset it before reading anything."
  (handler-case
      (progn
        (reset-cpu-state!)
        (memory-reset!)
        (display-reset!)
        (load-fontset-into-memory!)
        (load-rom-file! path)
        (keypad-reset!)
        (dotimes (instruction budget)
          (execute-instruction!))
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
Returns a list of (PATHNAME OUTCOME CONDITION), one per ROM, in ROMS' order.
Resets the machine afterwards so the next spec in the run does not inherit the
last ROM's memory image."
  (prog1
      (loop for rom in roms
            collect (multiple-value-bind (outcome condition) (%run-corpus-rom rom budget)
                      (list rom outcome condition)))
    (reset-cpu-state!)
    (memory-reset!)
    (display-reset!)))

(defun %printable-corpus-name (path)
  "Return PATH's filename with control characters replaced by `.'.

The corpus is a third-party tree the operator points us at, so a filename is
untrusted text that this suite prints straight to the terminal. A ROM named
with embedded ANSI escapes would otherwise rewrite the reporter's output --
recolouring it, erasing lines, or hiding the very failure being reported.
Replacing rather than stripping keeps the length honest, so two names that
differ only in control characters do not collapse into one."
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
  "Return an alist of (OUTCOME . COUNT) covering *ROM-CORPUS-OUTCOME-ORDER*.
Every class appears even at zero, so a report that lists no faults is
distinguishable from one that forgot to look for them."
  (loop for class in *rom-corpus-outcome-order*
        collect (cons class
                      (count class outcomes :key #'second))))

(defun %report-corpus-summary (root budget outcomes stream)
  "Write the per-class tally to STREAM. These are the numbers that go in the
docs, so they name the corpus root and the budget that produced them."
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
  "5F0F: family 5's only clause is 5XY0 (SE Vx, Vy), which requires a low
nibble of 0 (src/opcodes.lisp:202-212). 5F0F therefore matches no STEP clause
and EXECUTE-INSTRUCTION! signals CHIP8-INVALID-OPCODE -- the same outcome a
SUPER-CHIP or XO-CHIP program in the corpus produces."
  (%corpus-bytes #x5F #x0F))

(defun %out-of-bounds-rom-bytes ()
  "AFFF: LD I, 0xFFF, then F165: LD V0..V1, [I].
The register-block load spans two bytes from address 4095, so it runs one byte
past the 4096-byte address space and CHECK-MEMORY-ACCESS signals
CHIP8-MEMORY-ACCESS-OUT-OF-BOUNDS."
  (%corpus-bytes #xAF #xFF #xF1 #x65))

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
  "Write BYTES to NAME under directory ROOT and return the pathname.
NAME may name a subdirectory (\"nested/demo.ch8\"), which is created. Mirrors
t/rom-test.lisp's own /tmp-based temporary ROM helper; this target is
SBCL-only, so a plain /tmp path avoids depending on any particular external
temporary-file API."
  (let ((path (merge-pathnames name (host-kit:ensure-directory-pathname root))))
    (ensure-directories-exist path)
    (with-open-file (stream path :direction :output :if-exists :supersede
                                 :element-type '(unsigned-byte 8))
      (write-sequence bytes stream))
    path))

(defun %call-with-temp-corpus (thunk)
  "Create a fresh temporary corpus directory, call THUNK with it, delete it."
  (let ((root (merge-pathnames
               (format nil "cl-chip8-corpus-test-~D-~D/"
                       (get-universal-time) (random 1000000))
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

(describe "chip8Archive ROM corpus smoke test (FR-010)"
  (it "runs every .ch8 ROM under CL_CHIP8_ROM_CORPUS with no memory or stack fault"
    (let ((root (%corpus-root)))
      ;; An unconfigured corpus is reported as a skip.
      (unless root
        (skip (format nil "~A is unset. Set it to a directory tree of .ch8 files ~
                           (for example a clone of JohnEarnest/chip8Archive) to run ~
                           the corpus smoke test."
                      *rom-corpus-root-variable*)))
      ;; A configured but missing directory is an error.
      (unless (host-kit:directory-exists-p root)
        (error "~A names ~A, which is not an existing directory."
               *rom-corpus-root-variable* root))
      (let ((budget (%corpus-budget))
            (roms (%corpus-rom-files root)))
        ;; Require at least one ROM when a corpus is configured.
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
    ;; This is the empty-corpus case rejected by the smoke-test gate.
    (with-temp-corpus (root)
      (expect (%corpus-rom-files root) :to-equal '()))))

(describe "ROM corpus fault-report sanitisation"
  ;; A corpus is a third-party tree, so a ROM filename is untrusted text that
  ;; this suite prints to the terminal. These exercise the function directly
  ;; rather than through the filesystem: a control character in a real
  ;; filename is awkward to create portably, and the property under test
  ;; belongs to the formatting, not to discovery.
  (it "replaces an escape sequence in a ROM name so it cannot rewrite the report"
    (let ((sanitised (%printable-corpus-name
                      (make-pathname :name (format nil "evil~C[2K" (code-char 27))
                                     :type "ch8"))))
      (with-soft-assertions
        (expect (find (code-char 27) sanitised) :to-be nil)
        (expect (search "evil" sanitised) :to-be 0))))
  (it "replaces rather than strips, so names differing only in control characters stay distinct"
    (let ((a (%printable-corpus-name
              (make-pathname :name (format nil "rom~C" (code-char 7)) :type "ch8")))
          (b (%printable-corpus-name
              (make-pathname :name "rom" :type "ch8"))))
      (expect (string= a b) :to-be nil)))
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
  (it "reports an out-of-bounds register-block load as a memory fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "oob.ch8" (%out-of-bounds-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :memory-access-out-of-bounds))))
  (it "reports RET on an empty call stack as a stack fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "underflow.ch8" (%stack-underflow-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :stack-underflow))))
  (it "reports a runaway CALL chain as a stack fault"
    (with-temp-corpus (root)
      (let ((rom (%write-corpus-rom root "overflow.ch8" (%stack-overflow-rom-bytes))))
        (expect (%run-corpus-rom rom 2000) :to-be :stack-overflow)))))

(describe "ROM corpus fault reporting"
  (it "reports no fault for a corpus of clean and merely-unsupported ROMs"
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
    ;; Ensure fault outcomes identify the offending ROM.
    (with-temp-corpus (root)
      (%write-corpus-rom root "loop.ch8" (%looping-rom-bytes))
      (%write-corpus-rom root "oob.ch8" (%out-of-bounds-rom-bytes))
      (let ((faults (%corpus-faults (%corpus-outcomes (%corpus-rom-files root) 2000))))
        (with-soft-assertions
          (expect (length faults) :to-be 1)
          (expect (search "oob.ch8" (first faults)) :to-be 0)
          (expect (integerp (search "memory-access-out-of-bounds" (first faults)))
                  :to-be t))))))
