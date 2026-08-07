;;;; src/opcodes.lisp -- the instruction rulebase: all 35 CHIP-8 opcodes.
;;;;
;;;; Architecture recap (see cl-chip8.asd's :long-description and the README):
;;;; instruction dispatch is driven by genuine Prolog goal resolution over
;;;; *RULEBASE*, not a Lisp COND/CASE. A 16-bit opcode is fetched from
;;;; *MEMORY* at the current PC and decoded in Lisp into six plain integers
;;;; -- (FAMILY X Y N KK NNN), the top nibble, second nibble, third nibble,
;;;; fourth nibble, last byte, and last three nibbles -- and EXECUTE-
;;;; INSTRUCTION! resolves exactly one `(step Family X Y N Kk Nnn)' goal
;;;; against the ~35-clause STEP/6 rulebase below. Which clause fires is
;;;; decided by real unification: FAMILY gives cl-prolog's first-argument
;;;; indexing its top-level split, and within a family, N or KK (already
;;;; bound to a concrete integer by the caller) unifies against a literal in
;;;; the clause head to pick the sub-opcode -- e.g. `8XY6' and `8XY7' are two
;;;; different STEP clauses distinguished purely by N unifying with 6 or 7,
;;;; not by an if/case reading N in Lisp. `:when' guards (a cl-prolog DSL
;;;; feature that compiles to a plain Lisp closure over already-bound
;;;; variables -- see cl-prolog's rule-dsl.md) cover the handful of branches
;;;; that depend on a runtime VALUE rather than the static opcode pattern:
;;;; CALL's stack-depth check and SUB/SUBN's borrow flag.
;;;;
;;;; PC ownership: EVERY step clause below retracts and reasserts the `pc'
;;;; fact itself, including the ordinary case (old value + 2). This is a
;;;; deliberate simplification over one plausible split the brief sketches
;;;; -- "Lisp auto-advances PC by 2 except where an opcode sets it itself" --
;;;; which would require EXECUTE-INSTRUCTION! to know, for every family,
;;;; whether that opcode already moved PC, duplicating the opcode-family
;;;; knowledge that already lives in this rulebase. Making PC advancement
;;;; uniform (every clause owns it, no exceptions but FX0A's block-until-
;;;; keypress clause, which deliberately leaves PC untouched so the same
;;;; instruction re-fetches next cycle) keeps EXECUTE-INSTRUCTION! completely
;;;; ignorant of which opcode ran: it fetches, decodes, resolves STEP once,
;;;; and never touches PC itself.
;;;;
;;;; Ordering matters within a family: cl-prolog's first-argument indexing on
;;;; FAMILY is purely an optimization -- clauses of the same predicate are
;;;; still tried in the definition order this file lists them, per
;;;; cl-prolog's semantics.md. Family 0's three specific-NNN-value clauses
;;;; (00E0, 00EE non-empty stack, 00EE empty stack) are therefore listed
;;;; before its catch-all 0NNN/SYS clause, and EX9E/EXA1's guarded clause
;;;; comes before its unconditional fallback -- see each family's comment
;;;; below for why no explicit negation is needed for that fallback.
;;;;
;;;; A handful of small foreign predicates below bridge to Lisp for concerns
;;;; a pure Prolog clause body cannot express: signaling the CL conditions
;;;; CALL/RET need on stack overflow/underflow, iterating a sprite's rows and
;;;; bits (DXYN) or a register block (FX55/FX65), masking a random byte
;;;; (CXKK), and bitwise OR/AND/XOR (8XY1-8XY3) -- exactly the same
;;;; memory/display boundary stage 1 already established in memory.lisp and
;;;; display.lisp, extended to the opcode layer's own Lisp-side needs.
(in-package #:cl-chip8)

;;; --------------------------------------------------------------------------
;;; Fetch and decode: plain Lisp, no Prolog involved yet.
;;; --------------------------------------------------------------------------

(defun fetch-opcode ()
  "Return the 16-bit big-endian opcode at the current PC, read from *MEMORY*."
  (let* ((solutions (query-prolog *rulebase* '(pc ?value)))
         (address (solution-binding '?value (first solutions))))
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
own body perform every state change, including advancing PC (see this file's
header comment on PC ownership). Signals CHIP8-INVALID-OPCODE when no STEP
clause matches the decoded opcode. Returns no values."
  (let ((opcode (fetch-opcode)))
    (multiple-value-bind (family x y n kk nnn) (decode-opcode opcode)
      (unless (prolog-succeeds-p *rulebase* (list 'step family x y n kk nnn))
        (error 'chip8-invalid-opcode :opcode opcode))))
  (values))

;;; --------------------------------------------------------------------------
;;; Foreign predicates: the Lisp-side primitives STEP clause bodies call into.
;;; --------------------------------------------------------------------------

;; Signal CHIP8-STACK-OVERFLOW for CALL when STACK (the current call-stack
;; list, already at +CALL-STACK-LIMIT+ entries) has no room for a 17th.
(define-foreign-predicate (raise-stack-overflow stack) (rulebase environment depth emit)
  (declare (ignore rulebase depth emit))
  (let ((resolved-stack (logic-substitute stack environment)))
    (error 'chip8-stack-overflow :depth (length resolved-stack))))

;; Signal CHIP8-STACK-UNDERFLOW for RET when the call stack is empty.
(define-foreign-predicate (raise-stack-underflow) (rulebase environment depth emit)
  (declare (ignore rulebase environment depth emit))
  (error 'chip8-stack-underflow))

;; Bind RESULT to the bitwise OR/AND/XOR of A and B, selected by OPERATION
;; (the plain symbol OR, AND, or XOR), for 8XY1/8XY2/8XY3. A dedicated
;; foreign predicate, rather than a Prolog-level bitwise operator, sidesteps
;; the backslash-escaped operator spellings ISO Prolog uses for bitwise
;; OR/AND (`\/', `/\') entirely.
(define-foreign-predicate (bitwise-op operation a b result)
    (rulebase environment depth emit)
  (declare (ignore depth))
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
  (declare (ignore rulebase depth))
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
(define-foreign-predicate (draw-sprite i vx vy n collision)
    (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (let ((resolved-i (logic-substitute i environment))
        (resolved-vx (logic-substitute vx environment))
        (resolved-vy (logic-substitute vy environment))
        (resolved-n (logic-substitute n environment))
        (collided 0))
    (check-memory-access resolved-i resolved-n)
    (dotimes (row resolved-n)
      (let ((byte (aref *memory* (+ resolved-i row)))
            (screen-y (+ resolved-vy row)))
        (when (< screen-y +display-height+)
          (dotimes (bit 8)
            (let ((screen-x (+ resolved-vx bit)))
              (when (and (< screen-x +display-width+) (logbitp (- 7 bit) byte))
                (when (display-xor-pixel! screen-x screen-y)
                  (setf collided 1))))))))
    (multiple-value-bind (extended ok) (unify collision collided environment)
      (when ok (funcall emit extended)))))

;; Copy registers V0..VX (inclusive) into *MEMORY* starting at address I, for
;; FX55. I itself is left unchanged by design (the modern quirk this stage
;; commits to, per the brief).
(define-foreign-predicate (store-registers i x) (rulebase environment depth emit)
  (declare (ignore depth))
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
  (declare (ignore depth))
  (let ((resolved-i (logic-substitute i environment))
        (resolved-x (logic-substitute x environment)))
    (check-memory-access resolved-i (1+ resolved-x))
    (dotimes (index (1+ resolved-x))
      (let ((value (aref *memory* (+ resolved-i index))))
        (query-prolog rulebase (list 'retract (list 'v index (fresh-logic-variable))))
        (query-prolog rulebase (list 'assertz (list 'v index value)))))
    (funcall emit environment)))

;;; --------------------------------------------------------------------------
;;; The STEP/6 rulebase: all 35 CHIP-8 instructions.
;;; --------------------------------------------------------------------------
;;;
;;; A plain top-level SETF, not a DEFVAR/DEFPARAMETER: *RULEBASE* is already
;;; bound by state.lisp's own DEFVAR by the time this file loads (:SERIAL T
;;; in cl-chip8.asd), so a DEFVAR here would be a silent no-op (DEFVAR never
;;; rebinds an already-bound special variable) and these ~35 instructions
;;; would never actually be added. EXTEND-RULEBASE returns a new rulebase
;;; value that shadow-extends its base, so this SETF re-points *RULEBASE* at
;;; that extended value once, at load time, before RESET-CPU-STATE! (which
;;; only ever touches fact functors -- v, pc, i-register, and friends -- via
;;; RETRACTALL) has a chance to run.
(setf *rulebase*
      (extend-rulebase *rulebase*

        ;; -- Family 0: 00E0 CLS, 00EE RET, 0NNN SYS (no-op) --

        ;; 00E0 CLS: clear the display.
        ((step 0 ?x ?y ?n ?kk 224)
         (display-clear)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 00EE RET, non-empty call stack: pop it into PC. Combining the
        ;; empty/non-empty test with the mutation in one RETRACT is safe --
        ;; RETRACT only removes a fact when its pattern actually unifies, so
        ;; an empty stack (a bare NIL, not a cons) simply fails this clause
        ;; with no side effect, falling through to the next one below.
        ((step 0 ?x ?y ?n ?kk 238)
         (retract (call-stack (?return-address . ?rest)))
         (assertz (call-stack ?rest))
         (retract (pc ?old-pc))
         (assertz (pc ?return-address)))

        ;; 00EE RET, empty call stack: underflow.
        ((step 0 ?x ?y ?n ?kk 238)
         (call-stack nil)
         (raise-stack-underflow))

        ;; 0NNN SYS addr: ignored, per modern convention. Catch-all for
        ;; family 0 -- must stay after the two 00E0/00EE clauses above, since
        ;; its NNN is an unconstrained variable that would otherwise shadow
        ;; them.
        ((step 0 ?x ?y ?n ?kk ?nnn)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 1: 1NNN JP addr --

        ((step 1 ?x ?y ?n ?kk ?nnn)
         (retract (pc ?old-pc))
         (assertz (pc ?nnn)))

        ;; -- Family 2: 2NNN CALL addr --

        ;; Room on the call stack: push the return address (the instruction
        ;; after this CALL) and jump. The depth guard is tested (a
        ;; non-destructive fact read plus a pure :WHEN predicate) before any
        ;; mutation, so a guard failure here never leaves a half-applied CALL
        ;; behind for the overflow clause below to inherit.
        ;; The literal 16 below is +CALL-STACK-LIMIT+'s value (state.lisp):
        ;; cl-prolog's clause DSL quotes this body literally at
        ;; EXTEND-RULEBASE macro-expansion time (see cl-prolog's
        ;; dsl-compiler.lisp), so a symbolic reference to the Lisp constant
        ;; cannot be spliced in here -- the same constraint FX29's own
        ;; comment documents for +FONTSET-ADDRESS+.
        ((step 2 ?x ?y ?n ?kk ?nnn)
         (call-stack ?stack)
         (:when (< (length ?stack) 16))
         (pc ?old-pc)
         (is ?return-address (+ ?old-pc 2))
         (retract (call-stack ?stack))
         (assertz (call-stack (?return-address . ?stack)))
         (retract (pc ?old-pc))
         (assertz (pc ?nnn)))

        ;; No room: overflow. 16 is +CALL-STACK-LIMIT+'s value -- see the
        ;; comment on the guard clause just above for why it cannot be
        ;; spliced in symbolically.
        ((step 2 ?x ?y ?n ?kk ?nnn)
         (call-stack ?stack)
         (:when (>= (length ?stack) 16))
         (raise-stack-overflow ?stack))

        ;; -- Family 3: 3XKK SE Vx, byte --
        ;;
        ;; The equality test below is plain unification, not an arithmetic
        ;; comparison goal: (v ?x ?kk) reuses ?KK, already bound to the
        ;; literal byte STEP was called with, as register X's expected
        ;; current value, so the goal only succeeds when they are the same
        ;; number. This needs no `=:=' import at all.

        ;; Vx == KK: skip (pc+4).
        ((step 3 ?x ?y ?n ?kk ?nnn)
         (v ?x ?kk)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 4))
         (assertz (pc ?new-pc)))

        ;; Fallback, reached only when the equality test above failed to
        ;; unify: Vx != KK, no skip (pc+2).
        ((step 3 ?x ?y ?n ?kk ?nnn)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 4: 4XKK SNE Vx, byte -- the mirror image of family 3. --

        ((step 4 ?x ?y ?n ?kk ?nnn)
         (v ?x ?kk)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ((step 4 ?x ?y ?n ?kk ?nnn)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 4))
         (assertz (pc ?new-pc)))

        ;; -- Family 5: 5XY0 SE Vx, Vy --
        ;;
        ;; Vx == Vy is tested by reading both registers into the SAME shared
        ;; logic variable: the second (v ?y ?shared) only succeeds if Vy's
        ;; current value unifies with whatever Vx's read already bound
        ;; ?SHARED to. Again, no arithmetic comparison goal needed.

        ((step 5 ?x ?y 0 ?kk ?nnn)
         (v ?x ?shared)
         (v ?y ?shared)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 4))
         (assertz (pc ?new-pc)))

        ((step 5 ?x ?y 0 ?kk ?nnn)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 6: 6XKK LD Vx, byte --

        ((step 6 ?x ?y ?n ?kk ?nnn)
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?kk))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 7: 7XKK ADD Vx, byte (wraps mod 256, no VF) --

        ((step 7 ?x ?y ?n ?kk ?nnn)
         (retract (v ?x ?vx))
         (is ?sum (+ ?vx ?kk))
         (is ?wrapped (mod ?sum 256))
         (assertz (v ?x ?wrapped))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 8: the ALU family, sub-dispatched on N (8XY0-8XY7, 8XYE) --

        ;; 8XY0 LD Vx, Vy
        ((step 8 ?x ?y 0 ?kk ?nnn)
         (v ?y ?vy)
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?vy))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XY1 OR Vx, Vy
        ((step 8 ?x ?y 1 ?kk ?nnn)
         (v ?y ?vy)
         (retract (v ?x ?vx))
         (bitwise-op or ?vx ?vy ?result)
         (assertz (v ?x ?result))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XY2 AND Vx, Vy
        ((step 8 ?x ?y 2 ?kk ?nnn)
         (v ?y ?vy)
         (retract (v ?x ?vx))
         (bitwise-op and ?vx ?vy ?result)
         (assertz (v ?x ?result))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XY3 XOR Vx, Vy
        ((step 8 ?x ?y 3 ?kk ?nnn)
         (v ?y ?vy)
         (retract (v ?x ?vx))
         (bitwise-op xor ?vx ?vy ?result)
         (assertz (v ?x ?result))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XY4 ADD Vx, Vy, VF = carry. The maximum sum is 255+255=510, so
        ;; SUM // 256 is exactly 0 or 1 -- the carry bit -- with no guard
        ;; branch needed.
        ((step 8 ?x ?y 4 ?kk ?nnn)
         (v ?y ?vy)
         (retract (v ?x ?vx))
         (is ?sum (+ ?vx ?vy))
         (is ?wrapped (mod ?sum 256))
         (is ?carry (// ?sum 256))
         (assertz (v ?x ?wrapped))
         (retract (v 15 ?old-vf))
         (assertz (v 15 ?carry))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XY5 SUB Vx, Vy, VF = 1 if Vx > Vy else 0 (NOT borrow). Unlike
        ;; ADD's carry, "greater than" has no single arithmetic formula here,
        ;; so this is two guarded clauses, tested before any mutation.
        ((step 8 ?x ?y 5 ?kk ?nnn)
         (v ?x ?vx)
         (v ?y ?vy)
         (:when (> ?vx ?vy))
         (is ?wrapped (mod (- ?vx ?vy) 256))
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?wrapped))
         (retract (v 15 ?old-vf))
         (assertz (v 15 1))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ((step 8 ?x ?y 5 ?kk ?nnn)
         (v ?x ?vx)
         (v ?y ?vy)
         (:when (<= ?vx ?vy))
         (is ?wrapped (mod (- ?vx ?vy) 256))
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?wrapped))
         (retract (v 15 ?old-vf))
         (assertz (v 15 0))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XY6 SHR Vx {, Vy}: VF = LSB of Vx before the shift, Vx >>= 1. VY
        ;; is read nowhere in this clause's body: the modern quirk this stage
        ;; commits to (VIP-authentic VY-as-source is out of scope).
        ((step 8 ?x ?y 6 ?kk ?nnn)
         (retract (v ?x ?vx))
         (is ?lsb (mod ?vx 2))
         (is ?shifted (// ?vx 2))
         (assertz (v ?x ?shifted))
         (retract (v 15 ?old-vf))
         (assertz (v 15 ?lsb))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XY7 SUBN Vx, Vy, VF = 1 if Vy > Vx else 0; Vx = Vy - Vx.
        ((step 8 ?x ?y 7 ?kk ?nnn)
         (v ?x ?vx)
         (v ?y ?vy)
         (:when (> ?vy ?vx))
         (is ?wrapped (mod (- ?vy ?vx) 256))
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?wrapped))
         (retract (v 15 ?old-vf))
         (assertz (v 15 1))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ((step 8 ?x ?y 7 ?kk ?nnn)
         (v ?x ?vx)
         (v ?y ?vy)
         (:when (<= ?vy ?vx))
         (is ?wrapped (mod (- ?vy ?vx) 256))
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?wrapped))
         (retract (v 15 ?old-vf))
         (assertz (v 15 0))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; 8XYE SHL Vx {, Vy}: VF = MSB of Vx before the shift, Vx <<= 1 mod
        ;; 256. VY ignored, same modern quirk as 8XY6.
        ((step 8 ?x ?y 14 ?kk ?nnn)
         (retract (v ?x ?vx))
         (is ?msb (// ?vx 128))
         (is ?shifted (mod (* ?vx 2) 256))
         (assertz (v ?x ?shifted))
         (retract (v 15 ?old-vf))
         (assertz (v 15 ?msb))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 9: 9XY0 SNE Vx, Vy -- the mirror image of family 5. --

        ((step 9 ?x ?y 0 ?kk ?nnn)
         (v ?x ?shared)
         (v ?y ?shared)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ((step 9 ?x ?y 0 ?kk ?nnn)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 4))
         (assertz (pc ?new-pc)))

        ;; -- Family 10 (A): ANNN LD I, addr --

        ((step 10 ?x ?y ?n ?kk ?nnn)
         (retract (i-register ?old-i))
         (assertz (i-register ?nnn))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 11 (B): BNNN JP V0, addr --

        ((step 11 ?x ?y ?n ?kk ?nnn)
         (v 0 ?v0)
         (is ?target (+ ?nnn ?v0))
         (retract (pc ?old-pc))
         (assertz (pc ?target)))

        ;; -- Family 12 (C): CXKK RND Vx, byte --

        ((step 12 ?x ?y ?n ?kk ?nnn)
         (random-byte-masked ?kk ?result)
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?result))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 13 (D): DXYN DRW Vx, Vy, nibble --

        ((step 13 ?x ?y ?n ?kk ?nnn)
         (v ?x ?vx)
         (v ?y ?vy)
         (i-register ?i)
         (draw-sprite ?i ?vx ?vy ?n ?collision)
         (retract (v 15 ?old-vf))
         (assertz (v 15 ?collision))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; -- Family 14 (E): EX9E SKP Vx, EXA1 SKNP Vx, sub-dispatched on KK --
        ;;
        ;; Neither fallback below needs an explicit negation-as-failure goal:
        ;; (key-down ?vx) simply has no solutions when that key is not
        ;; pressed, which is exactly Prolog's natural clause-fallback
        ;; trigger, so the second clause for each KK value is reached
        ;; precisely when the first one's key-down test failed.

        ;; EX9E SKP Vx: skip (pc+4) if key Vx is pressed.
        ((step 14 ?x ?y ?n 158 ?nnn)
         (v ?x ?vx)
         (key-down ?vx)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 4))
         (assertz (pc ?new-pc)))

        ((step 14 ?x ?y ?n 158 ?nnn)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; EXA1 SKNP Vx: skip (pc+4) if key Vx is NOT pressed.
        ((step 14 ?x ?y ?n 161 ?nnn)
         (v ?x ?vx)
         (key-down ?vx)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ((step 14 ?x ?y ?n 161 ?nnn)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 4))
         (assertz (pc ?new-pc)))

        ;; -- Family 15 (F): the FX__ family, sub-dispatched on KK --

        ;; FX07 LD Vx, DT
        ((step 15 ?x ?y ?n 7 ?nnn)
         (delay-timer ?dt)
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?dt))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX0A LD Vx, K: block until a key is pressed. A key is currently
        ;; down: take one (arbitrarily, the first KEY-DOWN solution), store
        ;; it, and advance PC.
        ((step 15 ?x ?y ?n 10 ?nnn)
         (key-down ?key)
         (retract (v ?x ?old-vx))
         (assertz (v ?x ?key))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; No key down: a bare fact (an empty body -- always succeeds,
        ;; touches nothing). PC is left untouched, so EXECUTE-INSTRUCTION!
        ;; re-fetches this exact same FX0A opcode next cycle, the simple
        ;; re-fetch-without-advancing approach the brief suggests.
        ((step 15 ?x ?y ?n 10 ?nnn))

        ;; FX15 LD DT, Vx
        ((step 15 ?x ?y ?n 21 ?nnn)
         (v ?x ?vx)
         (retract (delay-timer ?old-dt))
         (assertz (delay-timer ?vx))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX18 LD ST, Vx
        ((step 15 ?x ?y ?n 24 ?nnn)
         (v ?x ?vx)
         (retract (sound-timer ?old-st))
         (assertz (sound-timer ?vx))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX1E ADD I, Vx: no CHIP-8-standard overflow flag, VF untouched. I
        ;; wraps mod 65536 (16 bits), not mod 4096 (12 bits) like ANNN/BNNN's
        ;; NNN above: NNN is capped to 12 bits by the opcode ENCODING itself
        ;; (DECODE-OPCODE's (ldb (byte 12 0) ...)), a static fact about the
        ;; instruction, whereas FX1E's addend is a runtime register value
        ;; that repeated execution can push arbitrarily high with no encoding
        ;; to cap it -- unmasked, that is exactly finding #2 of the security
        ;; review this comment documents. 16 bits (not 12) is the deliberate
        ;; choice: some ROMs rely on I temporarily exceeding 0xFFF as an
        ;; overflow-detection trick (the "spaceflight" quirk), so masking to
        ;; 12 bits here would silently break a real ROM behavior this stage
        ;; has no other reason to reject. This does NOT reopen finding #1: I
        ;; being a 16-bit integer only bounds the register's own storage --
        ;; FX33/FX55/FX65/DXYN each still call CHECK-MEMORY-ACCESS (see
        ;; memory.lisp) before touching *MEMORY* through I, and that is what
        ;; actually rejects an I left outside [0, +MEMORY-SIZE+).
        ((step 15 ?x ?y ?n 30 ?nnn)
         (v ?x ?vx)
         (retract (i-register ?i))
         (is ?sum (+ ?i ?vx))
         (is ?new-i (mod ?sum 65536))
         (assertz (i-register ?new-i))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX29 LD F, Vx: I = fontset glyph address for the hex digit in Vx,
        ;; i.e. +FONTSET-ADDRESS+ (0x50 = 80) + 5 * Vx. The literal 80 below
        ;; is +FONTSET-ADDRESS+'s value: cl-prolog's clause DSL quotes this
        ;; body literally (see cl-prolog's dsl-compiler.lisp), so a symbolic
        ;; reference to the Lisp constant cannot be spliced in here.
        ((step 15 ?x ?y ?n 41 ?nnn)
         (v ?x ?vx)
         (is ?addr (+ 80 (* 5 ?vx)))
         (retract (i-register ?old-i))
         (assertz (i-register ?addr))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX33 LD B, Vx: store the 3 BCD digits of Vx at memory[I],
        ;; memory[I+1], memory[I+2], reusing stage 1's MEMORY-WRITE
        ;; primitive for every byte written.
        ((step 15 ?x ?y ?n 51 ?nnn)
         (v ?x ?vx)
         (i-register ?i)
         (is ?hundreds (// ?vx 100))
         (is ?tens (mod (// ?vx 10) 10))
         (is ?ones (mod ?vx 10))
         (memory-write ?i ?hundreds)
         (is ?i1 (+ ?i 1))
         (memory-write ?i1 ?tens)
         (is ?i2 (+ ?i 2))
         (memory-write ?i2 ?ones)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX55 LD [I], Vx: store V0..Vx at I, I unchanged (modern quirk).
        ((step 15 ?x ?y ?n 85 ?nnn)
         (i-register ?i)
         (store-registers ?i ?x)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX65 LD Vx, [I]: load V0..Vx from I, I unchanged (modern quirk).
        ((step 15 ?x ?y ?n 101 ?nnn)
         (i-register ?i)
         (load-registers ?i ?x)
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))))
