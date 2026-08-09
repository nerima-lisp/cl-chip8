;;;; t/opcodes-alu-test.lisp -- 6XKK, 7XKK, and the 8XY* ALU family.
;;;;
;;;; On VF assertions: RESET-MACHINE! zeroes all 16 registers, VF included
;;;; (src/state.lisp:61-62 asserts `(v index 0)` for every index). An
;;;; expectation that VF is 0 after an opcode is therefore satisfied by the
;;;; fixture alone -- it would still pass if the opcode never wrote VF, or
;;;; wrote the wrong value and something else zeroed it. Every such test below
;;;; seeds VF with +VF-SENTINEL+ before acting, so only a write performed by
;;;; the opcode under test can produce the expected 0. Assertions that expect
;;;; VF to be 1 need no sentinel: 0 is already the pre-act value, so 1 can only
;;;; come from the opcode.
(in-package #:cl-chip8/test)

(defparameter +vf-sentinel+ #xAA
  "A nonzero VF seed distinct from every VF value an ALU opcode can produce
(only 0 and 1), so an assertion on VF fails unless the opcode wrote it.")

(describe "6XKK LD Vx, byte"
  (before-each (reset-machine!))
  (it "sets Vx to KK and advances PC by 2"
    (run-instruction! #x600A)
    (with-soft-assertions
      (expect (register-value 0) :to-be #x0A)
      (expect (pc-value) :to-be (+ +rom-load-address+ 2)))))

(describe "7XKK ADD Vx, byte"
  (before-each (reset-machine!))
  (it "adds without wrapping when the sum fits in a byte"
    (set-register! 0 5)
    (run-instruction! #x7003)
    (expect (register-value 0) :to-be 8))
  (it "wraps mod 256 and leaves VF untouched"
    (set-register! 0 250)
    ;; 7XKK's clause (src/opcodes.lisp:225-232) asserts no `(v 15 ...)` fact at
    ;; all, so the contract is "VF is unchanged", not "VF is 0". Seeding the
    ;; sentinel is what distinguishes the two: without it the assertion holds
    ;; even for an implementation that clobbers VF with 0.
    (set-register! 15 +vf-sentinel+)
    (run-instruction! #x700A)
    (with-soft-assertions
      (expect (register-value 0) :to-be 4)
      (expect (register-value 15) :to-be +vf-sentinel+))))

(describe "8XY0 LD Vx, Vy"
  (before-each (reset-machine!))
  (it "copies Vy into Vx"
    (set-register! 1 42)
    (run-instruction! #x8010)
    (expect (register-value 0) :to-be 42)))

(describe "8XY1 OR Vx, Vy"
  (before-each (reset-machine!))
  (it "bitwise-ORs Vx and Vy into Vx"
    (set-register! 0 10)
    (set-register! 1 5)
    (run-instruction! #x8011)
    (expect (register-value 0) :to-be 15)))

(describe "8XY2 AND Vx, Vy"
  (before-each (reset-machine!))
  (it "bitwise-ANDs Vx and Vy into Vx"
    (set-register! 0 12)
    (set-register! 1 10)
    (run-instruction! #x8012)
    (expect (register-value 0) :to-be 8)))

(describe "8XY3 XOR Vx, Vy"
  (before-each (reset-machine!))
  (it "bitwise-XORs Vx and Vy into Vx"
    (set-register! 0 12)
    (set-register! 1 10)
    (run-instruction! #x8013)
    (expect (register-value 0) :to-be 6)))

(describe "8XY4 ADD Vx, Vy"
  (before-each (reset-machine!))
  (it "sets VF to 0 and the sum when it fits in a byte"
    (set-register! 0 10)
    (set-register! 1 20)
    ;; The carry write is src/opcodes.lisp:285-286; the sentinel is what makes
    ;; that write, rather than the fixture, responsible for the expected 0.
    (set-register! 15 +vf-sentinel+)
    (run-instruction! #x8014)
    (with-soft-assertions
      (expect (register-value 0) :to-be 30)
      (expect (register-value 15) :to-be 0)))
  (it "sets VF to 1 and wraps mod 256 on carry"
    (set-register! 0 200)
    (set-register! 1 100)
    (run-instruction! #x8014)
    (with-soft-assertions
      (expect (register-value 0) :to-be 44)
      (expect (register-value 15) :to-be 1))))

(describe "8XY5 SUB Vx, Vy"
  (before-each (reset-machine!))
  (it "sets VF to 1 (not borrow) and subtracts when Vx > Vy"
    (set-register! 0 10)
    (set-register! 1 3)
    (run-instruction! #x8015)
    (with-soft-assertions
      (expect (register-value 0) :to-be 7)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 1 and produces zero when operands are equal"
    (set-register! 0 10)
    (set-register! 1 10)
    (run-instruction! #x8015)
    (with-soft-assertions
      (expect (register-value 0) :to-be 0)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 and wraps mod 256 when Vx < Vy"
    (set-register! 0 3)
    (set-register! 1 10)
    ;; Borrow clause src/opcodes.lisp:307-318 writes `(v 15 0)`.
    (set-register! 15 +vf-sentinel+)
    (run-instruction! #x8015)
    (with-soft-assertions
      (expect (register-value 0) :to-be 249)
      (expect (register-value 15) :to-be 0))))

(describe "8XY6 SHR Vx {, Vy}"
  (before-each (reset-machine!))
  (it "sets VF to Vx's least-significant bit and halves Vx (odd case)"
    (set-register! 0 181)
    (run-instruction! #x8016)
    (with-soft-assertions
      (expect (register-value 0) :to-be 90)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 and halves Vx (even case)"
    (set-register! 0 180)
    ;; SHR writes the pre-shift LSB into VF (src/opcodes.lisp:328-329).
    (set-register! 15 +vf-sentinel+)
    (run-instruction! #x8016)
    (with-soft-assertions
      (expect (register-value 0) :to-be 90)
      (expect (register-value 15) :to-be 0)))
  (it "ignores Vy (the modern quirk this stage commits to)"
    (set-register! 0 180)
    (set-register! 1 255)
    (run-instruction! #x8016)
    (expect (register-value 0) :to-be 90)))

(describe "8XY7 SUBN Vx, Vy"
  (before-each (reset-machine!))
  (it "sets VF to 1 (not borrow) and Vx = Vy - Vx when Vy > Vx"
    (set-register! 0 3)
    (set-register! 1 10)
    (run-instruction! #x8017)
    (with-soft-assertions
      (expect (register-value 0) :to-be 7)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 1 and produces zero when operands are equal"
    (set-register! 0 10)
    (set-register! 1 10)
    (run-instruction! #x8017)
    (with-soft-assertions
      (expect (register-value 0) :to-be 0)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 and wraps mod 256 when Vy < Vx"
    (set-register! 0 10)
    (set-register! 1 3)
    ;; Borrow clause src/opcodes.lisp:348-359 writes `(v 15 0)`.
    (set-register! 15 +vf-sentinel+)
    (run-instruction! #x8017)
    (with-soft-assertions
      (expect (register-value 0) :to-be 249)
      (expect (register-value 15) :to-be 0))))

(describe "8XYE SHL Vx {, Vy}"
  (before-each (reset-machine!))
  (it "sets VF to Vx's most-significant bit and doubles Vx mod 256"
    (set-register! 0 192)
    (run-instruction! #x801E)
    (with-soft-assertions
      (expect (register-value 0) :to-be 128)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 when the most-significant bit is clear"
    (set-register! 0 64)
    ;; SHL writes the pre-shift MSB into VF (src/opcodes.lisp:368-369).
    (set-register! 15 +vf-sentinel+)
    (run-instruction! #x801E)
    (with-soft-assertions
      (expect (register-value 0) :to-be 128)
      (expect (register-value 15) :to-be 0)))
  (it "ignores Vy (the modern quirk this stage commits to)"
    (set-register! 0 192)
    (set-register! 1 255)
    (run-instruction! #x801E)
    (with-soft-assertions
      (expect (register-value 0) :to-be 128)
      (expect (register-value 15) :to-be 1))))
