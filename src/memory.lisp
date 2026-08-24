;;;; src/memory.lisp -- the 4096-byte CHIP-8 address space.
;;;;
;;;; Modeling every byte as an individual Prolog fact would make RETRACT and
;;;; RETRACTALL (which linearly scan every clause in the module) prohibitively
;;;; expensive for a 4096-entry space that changes every instruction. Memory
;;;; is therefore a plain Lisp array for O(1) AREF, wrapped by
;;;; DEFINE-FOREIGN-PREDICATE below so opcode goals (a later stage's concern)
;;;; can still read and write it from within Prolog proof search. This is the
;;;; one deliberate exception to "CPU state lives entirely in the rulebase" --
;;;; see the repository README and cl-chip8.asd's :long-description.
(in-package #:cl-chip8)

(declaim (inline memory-reset! check-memory-access %checked-memory-index))

(defun memory-reset! ()
  "Zero every byte of *MEMORY* in place and return it."
  (fill *memory* 0)
  *memory*)

(defun load-bytes-into-memory (bytes address)
  "Copy the octet vector BYTES into *MEMORY* starting at ADDRESS and return
BYTES. Signals CHIP8-MEMORY-ACCESS-OUT-OF-BOUNDS for a negative or beyond-end
ADDRESS, and CHIP8-ROM-TOO-LARGE when BYTES would run past the end of the
4096-byte address space."
  (check-type bytes vector)
  (check-type address integer)
  (loop for byte across bytes do (check-type byte chip8-octet))
  (let ((size (length bytes)))
    (cond
      ((or (minusp address) (> address +memory-size+))
       (error (quote chip8-memory-access-out-of-bounds)
              :address address
              :span size))
      ((> size (- +memory-size+ address))
       (error (quote chip8-rom-too-large)
              :size size
              :available (- +memory-size+ address)))
      (t
       (replace *memory* bytes :start1 address)
       bytes))))

(defun check-memory-access (address span)
  "Signal CHIP8-MEMORY-ACCESS-OUT-OF-BOUNDS unless every byte in
[ADDRESS, ADDRESS + SPAN) lies within *MEMORY*'s valid index range,
[0, +MEMORY-SIZE+). SPAN is 1 for a single-byte access; a caller iterating
several bytes starting at ADDRESS (FX55/FX65's register block, DXYN's sprite
rows) passes its own SPAN so the whole range is validated up front, before
any element of it is touched, rather than only its first byte.

This is the sole bounds-checking chokepoint for opcode-driven memory access.
MEMORY-READ/MEMORY-WRITE below call it for every foreign-predicate access
(which covers FX33's BCD store, itself built on MEMORY-WRITE). STORE-
REGISTERS, LOAD-REGISTERS, and DRAW-SPRITE in opcodes.lisp loop AREF directly
against *MEMORY* instead of going through those two primitives -- see this
file's own header comment and opcodes.lisp's DRAW-SPRITE comment for why --
so each of those three calls this function once before its loop rather than
repeating the bounds arithmetic at every AREF site."
  (check-type address integer)
  (check-type span integer)
  (when (or (minusp address)
            (minusp span)
            (> (+ address span) +memory-size+))
    (error (quote chip8-memory-access-out-of-bounds)
           :address address
           :span span))
  (values))

(defun %checked-memory-index (address)
  "Validate ADDRESS as a single-byte access and return its specialized index."
  (check-memory-access address 1)
  (the chip8-memory-index address))

;;; Prolog-callable primitives. Opcode goals (a later stage) read and write
;;; memory exclusively through these two, keeping every access on the same
;;; O(1) AREF path whether it originates from Lisp or from proof search.

(define-foreign-predicate (memory-read address value) (rulebase environment depth emit)
  (let ((resolved-address
          (%checked-memory-index (logic-substitute address environment))))
    (multiple-value-bind (extended ok)
        (unify value (aref *memory* resolved-address) environment)
      (when ok (funcall emit extended)))))

(define-foreign-predicate (memory-write address value) (rulebase environment depth emit)
  (let ((resolved-address
          (%checked-memory-index (logic-substitute address environment)))
        (resolved-value (logic-substitute value environment)))
    (check-type resolved-value chip8-octet)
    (setf (aref *memory* resolved-address) resolved-value)
    (funcall emit environment)))

(define-foreign-predicate (ensure-memory-range address span) (rulebase environment depth emit)
  (check-memory-access (logic-substitute address environment)
                       (logic-substitute span environment))
  (funcall emit environment))
