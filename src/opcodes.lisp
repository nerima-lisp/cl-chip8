;;;; The ordered STEP/6 rulebase for CHIP-8 instructions.
;;;;
;;;; EXECUTE-INSTRUCTION! decodes an opcode and resolves one STEP/6 goal.
;;;; Clauses are ordered from specific cases to family fallbacks.
(in-package #:cl-chip8)

;;; --------------------------------------------------------------------------
;;; The STEP/6 rulebase: all 35 CHIP-8 instructions.
;;; --------------------------------------------------------------------------
;;;
;;; Install the ordered opcode clauses once. CPU reset only changes dynamic
;;; facts and does not rebuild the rulebase.
(defvar *opcodes-installed-p* nil "True after the ordered opcode rulebase has been installed.")

(defmacro %extend-opcode-rulebase-once (base &body clauses)
  "Return BASE extended with CLAUSES, but never extend it twice.

The DSL quotes clause bodies before compiling them, so constants used in
guards and arithmetic goals must be substituted before the forms are passed to
the rulebase. Markers are replaced by their SYMBOL-VALUE during expansion."
  (let ((base-variable (gensym "BASE-"))
        (expanded-clauses
          (reduce (lambda (forms marker)
                    (subst (symbol-value marker) marker forms))
                  '(+call-stack-limit+ +fontset-address+ +memory-size+)
                  :initial-value clauses)))
    `(let ((,base-variable ,base))
       (if *opcodes-installed-p* ,base-variable
         (prog1
           (extend-rulebase ,base-variable ,@expanded-clauses)
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

        ;; 00EE RET, non-empty call stack: pop it into PC.
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

        ;; Room on the call stack: push the return address and jump.
        ((step 2 ?x ?y ?n ?kk ?nnn)
         (call-stack ?stack)
         (:when (< (length ?stack) +call-stack-limit+))
         (pc ?old-pc)
         (is ?return-address (+ ?old-pc 2))
         (retract (call-stack ?stack))
         (assertz (call-stack (?return-address . ?stack)))
         (retract (pc ?old-pc))
         (assertz (pc ?nnn)))

        ;; No room: overflow.
        ((step 2 ?x ?y ?n ?kk ?nnn)
         (call-stack ?stack)
         (:when (>= (length ?stack) +call-stack-limit+))
         (raise-stack-overflow ?stack))

        ;; -- Family 3: 3XKK SE Vx, byte --
        ;;
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
        ;; is read nowhere in this clause's body: this is the modern shift
        ;; quirk, not the VIP-authentic VY-as-source form.
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
        ;;
        ;; BNNN wraps the target to the 12-bit address space before updating PC.
        ((step 11 ?x ?y ?n ?kk ?nnn)
         (v 0 ?v0)
         (is ?target (mod (+ ?nnn ?v0) +memory-size+))
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

        ;; FX1E ADD I, Vx: VF is unchanged and I wraps modulo 65536.
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
        ;; i.e. +FONTSET-ADDRESS+ (0x50 = 80) + 5 * (Vx & 0xF).
        ;;
        ;; Vx is masked to a hexadecimal digit before calculating the glyph
        ;; address.
        ((step 15 ?x ?y ?n 41 ?nnn)
         (v ?x ?vx)
         (is ?addr (+ +fontset-address+ (* 5 (mod ?vx 16))))
         (retract (i-register ?old-i))
         (assertz (i-register ?addr))
         (retract (pc ?old-pc))
         (is ?new-pc (+ ?old-pc 2))
         (assertz (pc ?new-pc)))

        ;; FX33 LD B, Vx: store the 3 BCD digits of Vx at memory[I],
        ;; memory[I+1], memory[I+2], reusing memory.lisp's MEMORY-WRITE
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
