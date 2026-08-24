(in-package #:cl-chip8)

;;; --------------------------------------------------------------------------
;;; Fetch and decode: plain Lisp, no Prolog involved yet.
;;; --------------------------------------------------------------------------

(declaim (inline fetch-opcode decode-opcode)
         (ftype (function () chip8-opcode) fetch-opcode)
         (ftype (function (chip8-opcode)
                          (values chip8-nibble
                                  chip8-nibble
                                  chip8-nibble
                                  chip8-nibble
                                  chip8-octet
                                  chip8-memory-index))
                decode-opcode))

(defun fetch-opcode ()
  "Return the 16-bit big-endian opcode at the current PC, read from *MEMORY*."
  (let* ((solution (query-prolog-first *rulebase* '(pc ?value)))
         (raw-address (solution-binding '?value solution))
         (address (progn
                    (check-memory-access raw-address 2)
                    (the chip8-memory-index raw-address)))
         (high-byte (aref *memory* address))
         (low-byte (aref *memory* (1+ address))))
    (declare (type chip8-octet high-byte low-byte))
    (the chip8-opcode (logior (ash high-byte 8) low-byte))))

(defun decode-opcode (opcode)
  "Return (VALUES FAMILY X Y N KK NNN) for the 16-bit OPCODE: the top nibble,
second nibble, third nibble, fourth nibble, last byte, and last three
nibbles, respectively."
  (check-type opcode chip8-opcode)
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
      (declare (type chip8-nibble family x y n)
               (type chip8-octet kk)
               (type chip8-memory-index nnn))
      (unless (prolog-succeeds-p *rulebase* (list 'step family x y n kk nnn))
        (error 'chip8-invalid-opcode :opcode opcode))))
  (values))
