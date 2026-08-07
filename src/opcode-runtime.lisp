(in-package #:cl-chip8)

;;; --------------------------------------------------------------------------
;;; Fetch and decode: plain Lisp, no Prolog involved yet.
;;; --------------------------------------------------------------------------

(defun fetch-opcode ()
  "Return the 16-bit big-endian opcode at the current PC, read from *MEMORY*."
  (let* ((solutions (query-prolog *rulebase* '(pc ?value)))
         (address (solution-binding '?value (first solutions))))
    (check-memory-access address 2)
    (logior (ash (aref *memory* address) 8) (aref *memory* (1+ address)))))

(defun decode-opcode (opcode)
  "Return (VALUES FAMILY X Y N KK NNN) for the 16-bit OPCODE: the top nibble,
second nibble, third nibble, fourth nibble, last byte, and last three
nibbles, respectively."
  (values (ldb (byte 4 12) opcode)
          (ldb (byte 4 8) opcode)
          (ldb (byte 4 4) opcode)
          (ldb (byte 4 0) opcode)
          (ldb (byte 8 0) opcode)
          (ldb (byte 12 0) opcode)))

(defun execute-instruction! ()
  "Fetch, decode, and execute exactly one CHIP-8 instruction: resolve a single
`(step Family X Y N Kk Nnn)' goal against *RULEBASE*, letting that clause's
own body perform every state change, including advancing PC (see the header
comment in src/opcodes.lisp for PC ownership). Signals CHIP8-INVALID-OPCODE when no STEP
clause matches the decoded opcode. Returns no values."
  (let ((opcode (fetch-opcode)))
    (multiple-value-bind (family x y n kk nnn) (decode-opcode opcode)
      (unless (prolog-succeeds-p *rulebase* (list 'step family x y n kk nnn))
        (error 'chip8-invalid-opcode :opcode opcode))))
  (values))
