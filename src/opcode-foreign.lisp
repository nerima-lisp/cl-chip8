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
    (let ((computed (ecase resolved-operation
                      (or (logior resolved-a resolved-b))
                      (and (logand resolved-a resolved-b))
                      (xor (logxor resolved-a resolved-b)))))
      (multiple-value-bind (extended ok) (unify result computed environment)
        (when ok (funcall emit extended))))))

;; Bind VALUE to a random byte (0-255) bitwise-ANDed with MASK, for CXKK.
(define-foreign-predicate (random-byte-masked mask value) (rulebase environment depth emit)
  (let* ((resolved-mask (logic-substitute mask environment))
         (result (logand (random 256) resolved-mask)))
    (multiple-value-bind (extended ok) (unify value result environment)
      (when ok (funcall emit extended)))))

;; Draw an N-byte sprite stored at memory address I onto *DISPLAY* at (VX,
;; VY), XOR-ing each bit via DISPLAY-XOR-PIXEL! as stage 1 intends, with
;; wraparound off: a pixel that would land outside the 64x32 field is simply
;; not drawn. Binds COLLISION to 1 if any XOR erased a previously set pixel,
;; else 0. This is DXYN's sprite-row/bit iteration, the opcode-layer concern
;; stage 1's own display.lisp explicitly leaves to this stage.
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
 (let ((resolved-i (logic-substitute i environment))
       (resolved-vx (logic-substitute vx environment))
       (resolved-vy (logic-substitute vy environment))
       (resolved-n (logic-substitute n environment))
       (collided 0))
   (check-memory-access resolved-i resolved-n)
   (dotimes (row resolved-n)
     (let ((byte (aref *memory* (+ resolved-i row)))
           (screen-y (+ resolved-vy row)))
       (when (and (<= 0 screen-y) (< screen-y +display-height+))
         (dotimes (bit 8)
           (let ((screen-x (+ resolved-vx bit)))
             (when (and
                    (<= 0 screen-x)
                    (< screen-x +display-width+)
                    (logbitp (- 7 bit) byte)
                    (display-xor-pixel! screen-x screen-y))
               (setf collided 1)))))))
   (multiple-value-bind (extended ok) (unify collision collided environment)
     (when ok
       (funcall emit extended)))))

;; Copy registers V0..VX (inclusive) into *MEMORY* starting at address I, for
;; FX55. I itself is left unchanged by design (the modern quirk this stage
;; commits to, per the brief).
(define-foreign-predicate (store-registers i x) (rulebase environment depth emit)
  (let ((resolved-i (logic-substitute i environment))
        (resolved-x (logic-substitute x environment)))
    (check-memory-access resolved-i (1+ resolved-x))
    (dotimes (index (1+ resolved-x))
      (let* ((solutions (query-prolog rulebase (list 'v index '?value)))
             (value (solution-binding '?value (first solutions))))
        (setf (aref *memory* (+ resolved-i index)) value)))
    (funcall emit environment)))

;; Load registers V0..VX (inclusive) from *MEMORY* starting at address I, for
;; FX65. I itself is left unchanged by design (the modern quirk this stage
;; commits to, per the brief).
(define-foreign-predicate (load-registers i x) (rulebase environment depth emit)
  (let ((resolved-i (logic-substitute i environment))
        (resolved-x (logic-substitute x environment)))
    (check-memory-access resolved-i (1+ resolved-x))
    (dotimes (index (1+ resolved-x))
      (let ((value (aref *memory* (+ resolved-i index))))
        (query-prolog rulebase (list 'retract (list 'v index (fresh-logic-variable))))
        (query-prolog rulebase (list 'assertz (list 'v index value)))))
    (funcall emit environment)))
