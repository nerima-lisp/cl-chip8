;;;; src/conditions.lisp -- the package's condition hierarchy.
;;;;
;;;; Every condition this package signals derives from CHIP8-ERROR, so a
;;;; caller can catch all of them with one HANDLER-CASE clause. Public
;;;; condition names carry the package prefix per CODING_STANDARD.md
;;;; "コンディションの設計".
(in-package #:cl-chip8)

(define-condition chip8-error (error) ()
  (:documentation "Base condition for every error this package signals."))

(defmacro define-chip8-condition (name (&rest slots) report-control &key documentation)
  "Define NAME as a CHIP8-ERROR subcondition, with one slot per (SLOT-NAME
READER) entry of SLOTS and a :REPORT that applies REPORT-CONTROL, a FORMAT
control string, to every slot's READER in SLOTS' own order. DOCUMENTATION, if
given, becomes NAME's :DOCUMENTATION.

Both this package's public conditions share that exact shape -- an
:INITARG/:READER pair per offending value, plus a report built only from
those readers -- so this macro is the declarative definition form for it, per
the nerima-lisp API standard's rule that a macro needs a reason beyond what
DEFINE-CONDITION alone already gives. Every argument is a name or a literal
string read at macro-expansion time, never a runtime value, so nothing here
needs gensym protection for evaluation order; CONDITION and STREAM below are
gensymed only so the expansion cannot capture a binding a caller's own code
happens to use.

    (define-chip8-condition chip8-stack-underflow ()
      \"RET was executed with an empty call stack.\"
      :documentation \"Signaled when RET has no return address to pop.\")

expands to a DEFINE-CONDITION of CHIP8-STACK-UNDERFLOW under CHIP8-ERROR with
no slots, a :REPORT lambda that applies that literal string to no arguments,
and that :DOCUMENTATION string."
  (let ((condition (gensym "CONDITION"))
        (stream (gensym "STREAM")))
    `(define-condition ,name (chip8-error)
       ,(mapcar (lambda (slot)
                  (destructuring-bind (slot-name reader) slot
                    (list slot-name :initarg (intern (symbol-name slot-name) :keyword)
                          :reader reader)))
                slots)
       (:report (lambda (,condition ,stream)
                  (format ,stream ,report-control
                          ,@(mapcar (lambda (slot) (list (second slot) condition)) slots))))
       ,@(when documentation `((:documentation ,documentation))))))

(define-chip8-condition chip8-rom-too-large
    ((size chip8-rom-too-large-size) (available chip8-rom-too-large-available))
  "ROM is ~D bytes but only ~D bytes are available from the load address to the end of memory."
  :documentation "Signaled by LOAD-BYTES-INTO-MEMORY when SIZE bytes do not
fit in the AVAILABLE space between the load address and the end of the
4096-byte address space.")

(define-chip8-condition chip8-invalid-opcode ((opcode chip8-invalid-opcode-opcode))
  "~4,'0X is not a recognized or implemented CHIP-8 opcode."
  :documentation "Signaled when the opcode decoder is given a 16-bit value
that does not match any known or implemented CHIP-8 instruction. Raised by
the opcode dispatch this stage does not yet implement.")

(define-chip8-condition chip8-stack-overflow ((depth chip8-stack-overflow-depth))
  "CALL exceeds the 16-level call stack, which is already ~D deep."
  :documentation "Signaled when CALL would push a 17th return address onto a
call stack already holding +CALL-STACK-LIMIT+ (16) entries.")

(define-chip8-condition chip8-stack-underflow ()
  "RET was executed with an empty call stack."
  :documentation "Signaled when RET has no return address to pop.")

(define-chip8-condition chip8-memory-access-out-of-bounds
    ((address chip8-memory-access-out-of-bounds-address)
     (span chip8-memory-access-out-of-bounds-span))
  "A memory access at ~D spanning ~D byte(s) falls outside the 4096-byte address space."
  :documentation "Signaled by CHECK-MEMORY-ACCESS (see memory.lisp) when an
opcode -- FX55/FX65's register block, FX33's BCD digits (via MEMORY-WRITE),
or DXYN's sprite bytes -- would read or write *MEMORY* outside its valid
[0, +MEMORY-SIZE+) index range, computed from a ROM-controlled I register
(plus an offset). Raised explicitly instead of relying on the implicit SBCL
array-bounds check on AREF, so a malformed ROM produces a documented
CHIP8-ERROR rather than an unspecified condition.")

(define-chip8-condition chip8-rom-not-regular-file
    ((path chip8-rom-not-regular-file-path))
  "~A exists but is not a regular file; refusing to read it as a CHIP-8 ROM."
  :documentation "Signaled by LOAD-ROM-FILE! when PATH resolves (PROBE-FILE
succeeds) but is not a regular file -- a FIFO or character device such as
/dev/zero can make FILE-LENGTH/READ-SEQUENCE return an unreliable length or
block indefinitely, so this is checked before the ROM path is ever opened for
reading. A PATH that does not resolve at all is left to the ordinary
FILE-ERROR the eventual OPEN raises, which is the more specific condition for
that case.")
