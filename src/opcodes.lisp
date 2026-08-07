;;;; src/opcodes.lisp -- the ordered STEP/6 rulebase: all 35 CHIP-8 opcodes.
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
;;;; The Lisp-side primitives used by these clauses live in
;;;; OPCODE-RUNTIME.LISP (fetch/decode/execute) and OPCODE-FOREIGN.LISP
;;;; (stack conditions, bitwise/random operations, sprite drawing, and
;;;; register transfers). Keeping those forms outside this ordered table
;;;; makes the rulebase easier to inspect without changing clause order.
(in-package #:cl-chip8)

;;; --------------------------------------------------------------------------
;;; The STEP/6 rulebase: all 35 CHIP-8 instructions.
;;; --------------------------------------------------------------------------
;;;
;;; *RULEBASE* is already bound by state.lisp's DEFVAR when this file loads
;;; (:SERIAL T in cl-chip8.asd). EXTEND-RULEBASE returns a new rulebase value
;;; that shadow-extends its base, so the guarded SETF below installs the
;;; ordered opcode clauses once and re-points *RULEBASE* at that value.
;;; Keeping the installation guard separate from RESET-CPU-STATE! is
;;; intentional: reset retracts dynamic CPU facts, while source reloads must
;;; not accumulate duplicate opcode clauses in the persistent rulebase.
(defvar *opcodes-installed-p* nil "True after the ordered opcode rulebase has been installed.")

(defmacro %extend-opcode-rulebase-once (base &body clauses)
  "Return BASE extended with CLAUSES, but never extend it twice."
  (let ((base-variable (gensym "BASE-")))
    `(let ((,base-variable ,base))
       (if *opcodes-installed-p* ,base-variable
         (prog1
           (extend-rulebase ,base-variable ,@clauses)
           (setf *opcodes-installed-p* t))))))

(setf *rulebase*
      (%extend-opcode-rulebase-once *rulebase*

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

        ;; 8XY5 SUB Vx, Vy, VF = 1 if Vx >= Vy else 0 (NOT borrow). Unlike
        ;; ADD's carry, the non-strict comparison is expressed with guarded
        ;; no-borrow and borrow clauses, tested before any mutation.
        ((step 8 ?x ?y 5 ?kk ?nnn)
         (v ?x ?vx)
         (v ?y ?vy)
         (:when (>= ?vx ?vy))
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
         (:when (< ?vx ?vy))
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

        ;; 8XY7 SUBN Vx, Vy, VF = 1 if Vy >= Vx else 0; Vx = Vy - Vx.
        ((step 8 ?x ?y 7 ?kk ?nnn)
         (v ?x ?vx)
         (v ?y ?vy)
         (:when (>= ?vy ?vx))
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
         (:when (< ?vy ?vx))
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
         (ensure-memory-range ?i 3)
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
