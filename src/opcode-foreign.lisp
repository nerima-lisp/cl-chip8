(in-package #:cl-chip8)

;;; --------------------------------------------------------------------------
;;; Foreign predicates: the Lisp-side primitives STEP clause bodies call into.
;;; --------------------------------------------------------------------------

;; Signal CHIP8-STACK-OVERFLOW for CALL when STACK (the current call-stack
;; list, already at +CALL-STACK-LIMIT+ entries) has no room for a 17th.
(define-foreign-predicate (raise-stack-overflow stack) (rulebase environment depth emit)
  (let ((resolved-stack (logic-substitute stack environment)))
    (error 'chip8-stack-overflow :depth (length resolved-stack))))

;; Signal CHIP8-STACK-UNDERFLOW for RET when the call stack is empty.
(define-foreign-predicate (raise-stack-underflow) (rulebase environment depth emit)
  (error 'chip8-stack-underflow))

;; Bind RESULT to the bitwise OR/AND/XOR of A and B, selected by OPERATION
;; (the plain symbol OR, AND, or XOR), for 8XY1/8XY2/8XY3. A dedicated
;; foreign predicate, rather than a Prolog-level bitwise operator, sidesteps
;; the backslash-escaped operator spellings ISO Prolog uses for bitwise
;; OR/AND (`\/', `/\') entirely.
(define-foreign-predicate (bitwise-op operation a b result)
    (rulebase environment depth emit)
  (let ((resolved-operation (logic-substitute operation environment))
        (resolved-a (logic-substitute a environment))
        (resolved-b (logic-substitute b environment)))
    (check-type resolved-a chip8-octet)
    (check-type resolved-b chip8-octet)
    (let ((computed (ecase resolved-operation
                      (or (logior resolved-a resolved-b))
                      (and (logand resolved-a resolved-b))
                      (xor (logxor resolved-a resolved-b)))))
      (multiple-value-bind (extended ok) (unify result computed environment)
        (when ok (funcall emit extended))))))

;; Bind VALUE to a random byte (0-255) bitwise-ANDed with MASK, for CXKK.
(define-foreign-predicate (random-byte-masked mask value) (rulebase environment depth emit)
  (let ((resolved-mask (logic-substitute mask environment)))
    (check-type resolved-mask chip8-octet)
    (let ((result (logand (random 256) resolved-mask)))
      (multiple-value-bind (extended ok) (unify value result environment)
        (when ok (funcall emit extended))))))

;; Draw an N-byte sprite stored at memory address I onto *DISPLAY* at (VX,
;; VY), XOR-ing each bit via DISPLAY-XOR-PIXEL!. Binds COLLISION to 1 if any
;; XOR erased a previously set pixel, else 0. This is DXYN's sprite-row/bit
;; iteration; display.lisp owns only the single-pixel XOR primitive.
;;
;; Wrapping is the mainstream CHIP-8 / COSMAC VIP split, and the two halves
;; are deliberately different. The sprite ORIGIN wraps modulo the display
;; (VX=70 draws at column 6, VY=40 at row 8, VX=64 at column 0), so MOD is
;; applied once to the resolved VX/VY below, before any row/bit offset is
;; added. The sprite BODY then CLIPS: a wrapped origin at column 60 draws
;; columns 60-63 and drops what would be 64-67 rather than folding them back
;; to columns 0-3. Applying MOD to the final coordinate instead would wrap
;; the body too, which is the behavior real ROMs do not expect.
;;
;; Because MOD's result is non-negative for a positive divisor, ORIGIN-X and
;; ORIGIN-Y are already in range and the row/bit offsets only ever push them
;; upward, so the lower-bound half of the old range test is unreachable and
;; is gone; only the upper-bound clip remains.
;;
;; This function, STORE-REGISTERS, and LOAD-REGISTERS below all read/write
;; *MEMORY* via direct AREF rather than the MEMORY-READ/MEMORY-WRITE foreign
;; predicates that back every other memory access in this file: each already
;; loops over a whole sprite row or register block on the Lisp side (a single
;; Prolog clause body cannot express that iteration itself), so routing every
;; byte of it through a foreign-predicate round trip would cost real
;; performance for no benefit. This is a deliberate bypass, not an oversight
;; -- and it is exactly why each of the three calls CHECK-MEMORY-ACCESS (see
;; memory.lisp) once before its loop: that primitive is the chokepoint
;; MEMORY-READ/MEMORY-WRITE get for free, so these three ask for it
;; explicitly instead.
(define-foreign-predicate
 (draw-sprite i vx vy n collision)
 (rulebase environment depth emit)
  (let* ((resolved-i (logic-substitute i environment))
        (resolved-vx (logic-substitute vx environment))
        (resolved-vy (logic-substitute vy environment))
        (resolved-n (logic-substitute n environment)))
   (check-type resolved-i chip8-memory-index)
   (check-type resolved-vx integer)
   (check-type resolved-vy integer)
   (check-type resolved-n chip8-nibble)
   (check-memory-access resolved-i resolved-n)
   (let ((base (the chip8-memory-index resolved-i))
         (origin-x (the display-column (mod resolved-vx +display-width+)))
         (origin-y (the display-row (mod resolved-vy +display-height+)))
         (visible-rows
           (the (integer 0 15)
                (min resolved-n (- +display-height+ origin-y))))
         (visible-bits
           (the (integer 0 8)
                (min 8 (- +display-width+ origin-x))))
         (collided 0))
     (declare (type display-column origin-x)
              (type display-row origin-y)
              (type (integer 0 15) visible-rows)
              (type (integer 0 8) visible-bits)
              (type (integer 0 1) collided))
     (with-display-lock
       (dotimes (row visible-rows)
         (declare (type fixnum row))
         (let ((byte (aref *memory*
                           (the chip8-memory-index (+ base row))))
               (screen-y (the display-row (+ origin-y row))))
           (declare (type chip8-octet byte))
           (let ((row-dirty-p nil))
             (dotimes (bit visible-bits)
               (declare (type fixnum bit))
               (when (logbitp (- 7 bit) byte)
                 (when (%display-xor-pixel-under-lock!
                        (the display-column (+ origin-x bit))
                        screen-y
                        nil)
                   (setf collided 1))
                 (setf row-dirty-p t)))
             (when row-dirty-p
               (%mark-display-row-dirty! screen-y)))))
     (multiple-value-bind (extended ok) (unify collision collided environment)
       (when ok
         (funcall emit extended)))))))

;; Copy registers V0..VX (inclusive) into *MEMORY* starting at address I, for
;; FX55. I itself is left unchanged by design (the modern quirk, not the
;; VIP-authentic I += X + 1).
(define-foreign-predicate (store-registers i x) (rulebase environment depth emit)
  (let ((resolved-i (logic-substitute i environment))
        (resolved-x (logic-substitute x environment)))
    (check-type resolved-i chip8-memory-index)
    (check-type resolved-x chip8-register-index)
    (check-memory-access resolved-i (1+ resolved-x))
    (let ((base (the chip8-memory-index resolved-i)))
      (dotimes (index (1+ resolved-x))
        (declare (type chip8-register-index index))
        (let* ((solution (query-prolog-first rulebase (list 'v index '?value)))
               (value (solution-binding '?value solution)))
          (check-type value chip8-octet)
          (setf (aref *memory*
                      (the chip8-memory-index (+ base index)))
                value))))
    (funcall emit environment)))

;; Load registers V0..VX (inclusive) from *MEMORY* starting at address I, for
;; FX65. I itself is left unchanged by design (the modern quirk, not the
;; VIP-authentic I += X + 1).
(define-foreign-predicate (load-registers i x) (rulebase environment depth emit)
  (let ((resolved-i (logic-substitute i environment))
        (resolved-x (logic-substitute x environment)))
    (check-type resolved-i chip8-memory-index)
    (check-type resolved-x chip8-register-index)
    (check-memory-access resolved-i (1+ resolved-x))
    (let ((base (the chip8-memory-index resolved-i)))
      (dotimes (index (1+ resolved-x))
        (declare (type chip8-register-index index))
        (let ((value (aref *memory*
                           (the chip8-memory-index (+ base index)))))
          (declare (type chip8-octet value))
          (query-prolog rulebase (list 'retract (list 'v index (fresh-logic-variable))))
          (query-prolog rulebase (list 'assertz (list 'v index value))))))
    (funcall emit environment)))
