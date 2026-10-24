;;;; Condition hierarchy.
(in-package #:cl-chip8)

(define-condition chip8-error (error)
  ()
  (:documentation "Base condition for every error this package signals."))

(defmacro define-chip8-condition (name
                                  (&rest slots)
                                  report-control
                                  &key
                                  documentation)
  "Define NAME as a CHIP8-ERROR subcondition.

Each item in SLOTS is a (SLOT-NAME READER) pair. REPORT-CONTROL is a FORMAT
control string applied to each reader in slot order. DOCUMENTATION, when
supplied, becomes the :DOCUMENTATION option on NAME.

The generated condition uses one :INITARG/:READER pair per slot and a :REPORT
that formats those reader values. The macro keeps these definitions
declarative; its arguments are names and literal strings read at macro
expansion, so only the generated CONDITION and STREAM bindings need gensyms
to avoid capturing caller bindings."
  (let ((condition (gensym "CONDITION"))
        (stream (gensym "STREAM")))
    `(define-condition ,name (chip8-error)
       ,(mapcar
         (lambda (slot)
           (destructuring-bind (slot-name reader) slot
             (list
              slot-name
              :initarg
              (intern (symbol-name slot-name) :keyword)
              :reader
              reader)))
         slots)
       (:report
        (lambda (,condition ,stream)
          ,@(unless slots
              `((declare (ignore ,condition))))
          (format
           ,stream
           ,report-control
           ,@(mapcar
              (lambda (slot)
                (list (second slot) condition))
              slots))))
       ,@(when documentation
           `((:documentation ,documentation))))))

(define-chip8-condition
 chip8-rom-empty
 ()
 "ROM contains no bytes."
 :documentation
 "Signaled when LOAD-ROM is given an empty byte vector.")

(define-chip8-condition
 chip8-rom-too-large
 ((size chip8-rom-too-large-size) (available chip8-rom-too-large-available))
 "ROM is ~D bytes but only ~D bytes are available from the load address to the end of memory."
 :documentation
 "Signaled by LOAD-BYTES-INTO-MEMORY when SIZE bytes do not
fit in the AVAILABLE bytes from the load address through the end of the
machine's memory.")

(define-chip8-condition
 chip8-rom-short-read
 ((actual-size chip8-rom-short-read-actual-size)
  (expected-size chip8-rom-short-read-expected-size))
 "ROM ended after ~D byte(s); expected ~D."
 :documentation
 "Signaled by %READ-ROM-FILE when READ-SEQUENCE reads fewer bytes than FILE-LENGTH reported. This prevents returning a byte vector whose unread tail contains zeroes.")

(define-chip8-condition
 chip8-invalid-opcode
 ((opcode chip8-invalid-opcode-opcode))
 "~4,'0X is not a recognized or implemented CHIP-8 opcode."
 :documentation
 "Signaled when the opcode decoder is given a 16-bit value
that does not match any known or implemented CHIP-8 instruction. cl-chip8
implements the original CHIP-8 set only, so SUPER-CHIP and XO-CHIP opcodes
reach this condition -- except those absorbed by the 0NNN SYS catch-all,
which are silently ignored instead. See docs/src/reference/compatibility.md
for the opcode-by-opcode split.")

(define-chip8-condition
 chip8-stack-overflow
 ((depth chip8-stack-overflow-depth))
 "CALL exceeds the 16-level call stack, which is already ~D deep."
 :documentation
 "Signaled when CALL would push a 17th return address onto a
call stack already holding +CALL-STACK-LIMIT+ (16) entries.")

(define-chip8-condition
 chip8-stack-underflow
 ()
 "RET was executed with an empty call stack."
 :documentation
 "Signaled when RET has no return address to pop.")

(define-chip8-condition
 chip8-memory-access-out-of-bounds
 ((address chip8-memory-access-out-of-bounds-address)
  (span chip8-memory-access-out-of-bounds-span))
 "A memory access at ~D spanning ~D byte(s) falls outside this machine's memory capacity."
 :documentation
 "Signaled when a memory operation uses an invalid address or a span outside the machine memory. The condition carries the rejected address and span in a CHIP8-ERROR instead of exposing an array bounds failure.")

(define-chip8-condition
 chip8-rom-not-regular-file
 ((path chip8-rom-not-regular-file-path))
 "~A exists but is not a regular file; refusing to read it as a CHIP-8 ROM."
 :documentation
 "Signaled by LOAD-ROM-FILE when PATH exists but is not a regular file, such as a FIFO or character device. FILE-LENGTH may be unreliable for these paths, and reads may block. A missing path is left to OPEN to signal as FILE-ERROR.")
(define-condition chip8-config-error (chip8-error)
  ((source-name :initarg :source-name :initform nil
                :reader chip8-config-error-source-name)
   (line :initarg :line :initform nil
         :reader chip8-config-error-line)
   (column :initarg :column :initform nil
           :reader chip8-config-error-column)
   (path :initarg :path :initform nil
         :reader chip8-config-error-path)
   (key :initarg :key :initform nil
        :reader chip8-config-error-key)
   (reason :initarg :reason :initform nil
           :reader chip8-config-error-reason))
  (:report
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
(define-chip8-condition
 chip8-unsupported-platform
 ((platform chip8-unsupported-platform-name))
 "ROM requires unsupported platform ~A."
 :documentation
 "Signaled before the application starts when a ROM database record lists only platforms that cl-chip8 does not implement. An explicit CLI platform or quirk profile bypasses this selection error.")
(defun %config-error (reason &key source-name line column path key)
  (error (quote chip8-config-error)
         :reason reason
         :source-name source-name
         :line line
         :column column
         :path path
         :key key))
