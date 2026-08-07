;;;; t/opcodes-flow-test.lisp -- 0NNN, 00E0, 00EE, 1NNN, 2NNN, 3XKK, 4XKK,
;;;; 5XY0, 9XY0, BNNN: control flow, the call stack, and the skip family.
(in-package #:cl-chip8/test)

(describe "0NNN SYS addr"
  (before-each (reset-machine!))
  (it "is ignored: PC advances by 2 and nothing else changes"
    (run-instruction! #x0123)
    (with-soft-assertions
      (expect (pc-value) :to-be (+ +rom-load-address+ 2))
      (expect (register-value 0) :to-be 0))))

(describe "00E0 CLS"
  (before-each (reset-machine!))
  (it "clears every pixel and advances PC by 2"
    (setf (aref *display* 5 5) 1)
    (run-instruction! #x00E0)
    (with-soft-assertions
      (expect (aref *display* 5 5) :to-be 0)
      (expect (pc-value) :to-be (+ +rom-load-address+ 2)))))

(describe "00EE RET"
  (before-each (reset-machine!))
  (it "pops the call stack into PC"
    (query-prolog *rulebase* (list 'retract (list 'call-stack nil)))
    (query-prolog *rulebase* (list 'assertz (list 'call-stack (list #x400))))
    (run-instruction! #x00EE)
    (with-soft-assertions
      (expect (pc-value) :to-be #x400)
      (expect (call-stack-value) :to-be nil)))
  (it "signals chip8-stack-underflow when the call stack is empty"
    (signals chip8-stack-underflow
      (run-instruction! #x00EE))))

(describe "1NNN JP addr"
  (before-each (reset-machine!))
  (it "sets PC to NNN"
    (run-instruction! #x1300)
    (expect (pc-value) :to-be #x300)))

(describe "2NNN CALL addr"
  (before-each (reset-machine!))
  (it "pushes the return address (PC + 2) and sets PC to NNN"
    (run-instruction! #x2300)
    (with-soft-assertions
      (expect (pc-value) :to-be #x300)
      (expect (call-stack-value) :to-equal (list (+ +rom-load-address+ 2)))))
  (it "signals chip8-stack-overflow on the 17th nested call"
    (dotimes (i 16)
      (run-instruction! #x2300 #x300))
    (expect (length (call-stack-value)) :to-be 16)
    (signals chip8-stack-overflow
      (run-instruction! #x2300 #x300))))

(describe "3XKK SE Vx, byte"
  (before-each (reset-machine!))
  (it "skips (pc+4) when Vx == KK"
    (set-register! 0 5)
    (run-instruction! #x3005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4)))
  (it "does not skip (pc+2) when Vx != KK"
    (set-register! 0 9)
    (run-instruction! #x3005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2))))

(describe "4XKK SNE Vx, byte"
  (before-each (reset-machine!))
  (it "does not skip (pc+2) when Vx == KK"
    (set-register! 0 5)
    (run-instruction! #x4005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2)))
  (it "skips (pc+4) when Vx != KK"
    (set-register! 0 9)
    (run-instruction! #x4005)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4))))

(describe "5XY0 SE Vx, Vy"
  (before-each (reset-machine!))
  (it "skips (pc+4) when Vx == Vy"
    (set-register! 0 7)
    (set-register! 1 7)
    (run-instruction! #x5010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4)))
  (it "does not skip (pc+2) when Vx != Vy"
    (set-register! 0 7)
    (set-register! 1 8)
    (run-instruction! #x5010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2))))

(describe "9XY0 SNE Vx, Vy"
  (before-each (reset-machine!))
  (it "does not skip (pc+2) when Vx == Vy"
    (set-register! 0 7)
    (set-register! 1 7)
    (run-instruction! #x9010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 2)))
  (it "skips (pc+4) when Vx != Vy"
    (set-register! 0 7)
    (set-register! 1 8)
    (run-instruction! #x9010)
    (expect (pc-value) :to-be (+ +rom-load-address+ 4))))

(describe "BNNN JP V0, addr"
  (before-each (reset-machine!))
  (it "sets PC to NNN + V0"
    (set-register! 0 #x10)
    (run-instruction! #xB300)
    (expect (pc-value) :to-be (+ #x300 #x10))))

(describe "opcode fetch memory bounds"
  (before-each (reset-machine!))
  (it "signals chip8-memory-access-out-of-bounds with address 4095 and span 2"
    (set-pc! (1- +memory-size+))
    (let ((condition
            (handler-case
                (progn (execute-instruction!) nil)
              (chip8-memory-access-out-of-bounds (c) c))))
      (expect condition :to-be-truthy)
      (when condition
        (with-soft-assertions
          (expect (chip8-memory-access-out-of-bounds-address condition) :to-be 4095)
          (expect (chip8-memory-access-out-of-bounds-span condition) :to-be 2))))))

(describe "invalid opcode dispatch"
  (before-each (reset-machine!))
  (it "signals chip8-invalid-opcode and leaves the program counter unchanged"
    (let ((condition
            (handler-case
                (progn (run-instruction! #x5011) nil)
              (chip8-invalid-opcode (c) c))))
      (expect condition :to-be-truthy)
      (when condition
        (with-soft-assertions
          (expect (chip8-invalid-opcode-opcode condition) :to-be #x5011)
          (expect (pc-value) :to-be +rom-load-address+))))))
(describe "opcode rulebase installation"
  (before-each (reset-machine!))
  (it "does not duplicate clauses when the opcode source is reloaded"
    (let* ((before-rulebase *rulebase*)
           (before-clause-count
             (length
               (cl-prolog:rulebase-visible-clauses before-rulebase))))
      (load (asdf:system-relative-pathname "cl-chip8" "src/opcodes.lisp"))
      (let ((after-clause-count
              (length
                (cl-prolog:rulebase-visible-clauses *rulebase*))))
        (with-soft-assertions
          (expect (eq *rulebase* before-rulebase) :to-be t)
          (expect after-clause-count :to-be before-clause-count))))))
