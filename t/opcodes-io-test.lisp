;;;; t/opcodes-io-test.lisp -- EX9E, EXA1, FX07, FX0A, FX15, FX18: keypad and
;;;; timer-reading instructions.
(in-package #:cl-chip8/test)

(describe "EX9E SKP Vx"
  (before-each (reset-machine!))
  (it "skips (pc+4) when key Vx is pressed"
    (set-register! 0 5)
    (query-prolog *rulebase* (list 'assertz (list 'key-down 5)))
    (run-instruction! #xE09E)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4)))
  (it "does not skip (pc+2) when key Vx is not pressed"
    (set-register! 0 5)
    (run-instruction! #xE09E)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2))))

(describe "EXA1 SKNP Vx"
  (before-each (reset-machine!))
  (it "does not skip (pc+2) when key Vx is pressed"
    (set-register! 0 5)
    (query-prolog *rulebase* (list 'assertz (list 'key-down 5)))
    (run-instruction! #xE0A1)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2)))
  (it "skips (pc+4) when key Vx is not pressed"
    (set-register! 0 5)
    (run-instruction! #xE0A1)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4))))

(describe "FX07 LD Vx, DT"
  (before-each (reset-machine!))
  (it "copies the delay timer into Vx"
    (set-delay-timer! 42)
    (run-instruction! #xF007)
    (expect (register-value 0) :to-be 42)))

(describe "FX0A LD Vx, K"
  (before-each (reset-machine!))
  (it "leaves PC unchanged when no key is pressed, so the instruction re-fetches"
    (run-instruction! #xF00A)
    (expect (pc-value) :to-be +rom-load-address+))
  (it "stores the pressed key's value and advances PC by 2"
    (query-prolog *rulebase* (list 'assertz (list 'key-down 7)))
    (run-instruction! #xF00A)
    (with-soft-assertions
      (expect (register-value 0) :to-be 7)
      (expect (pc-value) :to-be (+ +rom-load-address+ 2)))))

(describe "FX15 LD DT, Vx"
  (before-each (reset-machine!))
  (it "copies Vx into the delay timer"
    (set-register! 0 42)
    (run-instruction! #xF015)
    (expect (delay-timer-value) :to-be 42)))

(describe "FX18 LD ST, Vx"
  (before-each (reset-machine!))
  (it "copies Vx into the sound timer"
    (set-register! 0 42)
    (run-instruction! #xF018)
    (expect (sound-timer-value) :to-be 42)))
