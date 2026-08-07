;;;; t/opcodes-flow-test.lisp -- 0NNN, 00E0, 00EE, 1NNN, 2NNN, 3XKK, 4XKK,
;;;; 5XY0, 9XY0, BNNN: control flow, the call stack, and the skip family.
(in-package #:cl-chip8/test)

(describe "0NNN SYS addr"
  (it "is ignored: PC advances by 2 and nothing else changes"
    (reset-machine!)
    (run-instruction! #x0123)
    (with-soft-assertions
      (expect (pc-value) :to-be (+ +rom-load-address+ 2))
      (expect (register-value 0) :to-be 0))))

(describe "00E0 CLS"
  (it "clears every pixel and advances PC by 2"
    (reset-machine!)
    (setf (aref *display* 5 5) 1)
    (run-instruction! #x00E0)
    (with-soft-assertions
      (expect (aref *display* 5 5) :to-be 0)
      (expect (pc-value) :to-be (+ +rom-load-address+ 2)))))

(describe "00EE RET"
  (it "pops the call stack into PC"
    (reset-machine!)
    (query-prolog *rulebase* (list 'retract (list 'call-stack nil)))
    (query-prolog *rulebase* (list 'assertz (list 'call-stack (list #x400))))
    (run-instruction! #x00EE)
    (with-soft-assertions
      (expect (pc-value) :to-be #x400)
      (expect (call-stack-value) :to-be nil)))
  (it "signals chip8-stack-underflow when the call stack is empty"
    (reset-machine!)
    (signals chip8-stack-underflow
      (run-instruction! #x00EE))))

(describe "1NNN JP addr"
  (it "sets PC to NNN"
    (reset-machine!)
    (run-instruction! #x1300)
    (expect (pc-value) :to-be #x300)))

(describe "2NNN CALL addr"
  (it "pushes the return address (PC + 2) and sets PC to NNN"
    (reset-machine!)
    (run-instruction! #x2300)
    (with-soft-assertions
      (expect (pc-value) :to-be #x300)
      (expect (call-stack-value) :to-equal (list (+ +rom-load-address+ 2)))))
  (it "signals chip8-stack-overflow on the 17th nested call"
    (reset-machine!)
    (dotimes (i 16)
      (run-instruction! #x2300 #x300))
    (expect (length (call-stack-value)) :to-be 16)
    (signals chip8-stack-overflow
      (run-instruction! #x2300 #x300))))

(describe "3XKK SE Vx, byte"
  (it "skips (pc+4) when Vx == KK"
    (reset-machine!)
    (set-register! 0 5)
    (run-instruction! #x3005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4)))
  (it "does not skip (pc+2) when Vx != KK"
    (reset-machine!)
    (set-register! 0 9)
    (run-instruction! #x3005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2))))

(describe "4XKK SNE Vx, byte"
  (it "does not skip (pc+2) when Vx == KK"
    (reset-machine!)
    (set-register! 0 5)
    (run-instruction! #x4005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2)))
  (it "skips (pc+4) when Vx != KK"
    (reset-machine!)
    (set-register! 0 9)
    (run-instruction! #x4005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4))))

(describe "5XY0 SE Vx, Vy"
  (it "skips (pc+4) when Vx == Vy"
    (reset-machine!)
    (set-register! 0 7)
    (set-register! 1 7)
    (run-instruction! #x5010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4)))
  (it "does not skip (pc+2) when Vx != Vy"
    (reset-machine!)
    (set-register! 0 7)
    (set-register! 1 8)
    (run-instruction! #x5010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2))))

(describe "9XY0 SNE Vx, Vy"
  (it "does not skip (pc+2) when Vx == Vy"
    (reset-machine!)
    (set-register! 0 7)
    (set-register! 1 7)
    (run-instruction! #x9010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2)))
  (it "skips (pc+4) when Vx != Vy"
    (reset-machine!)
    (set-register! 0 7)
    (set-register! 1 8)
    (run-instruction! #x9010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4))))

(describe "BNNN JP V0, addr"
  (it "sets PC to NNN + V0"
    (reset-machine!)
    (set-register! 0 #x10)
    (run-instruction! #xB300)
    (expect (pc-value) :to-be (+ #x300 #x10))))
