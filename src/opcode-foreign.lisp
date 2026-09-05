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
;; The origin wraps modulo the display; sprite rows and bits clip at the
;; lower-right edge. Validate the sprite range once, then read *MEMORY*
;; directly while XORing pixels.
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
