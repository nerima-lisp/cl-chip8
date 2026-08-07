;;;; t/opcodes-alu-test.lisp -- 6XKK, 7XKK, and the 8XY* ALU family.
(in-package #:cl-chip8/test)

(describe "6XKK LD Vx, byte"
  (it "sets Vx to KK and advances PC by 2"
    (reset-machine!)
    (run-instruction! #x600A)
    (with-soft-assertions
      (expect (register-value 0) :to-be #x0A)
      (expect (pc-value) :to-be (+ +rom-load-address+ 2)))))

(describe "7XKK ADD Vx, byte"
  (it "adds without wrapping when the sum fits in a byte"
    (reset-machine!)
    (set-register! 0 5)
    (run-instruction! #x7003)
    (expect (register-value 0) :to-be 8))
  (it "wraps mod 256 and sets no flag"
    (reset-machine!)
    (set-register! 0 250)
    (run-instruction! #x700A)
    (with-soft-assertions
      (expect (register-value 0) :to-be 4)
      (expect (register-value 15) :to-be 0))))

(describe "8XY0 LD Vx, Vy"
  (it "copies Vy into Vx"
    (reset-machine!)
    (set-register! 1 42)
    (run-instruction! #x8010)
    (expect (register-value 0) :to-be 42)))

(describe "8XY1 OR Vx, Vy"
  (it "bitwise-ORs Vx and Vy into Vx"
    (reset-machine!)
    (set-register! 0 10)
    (set-register! 1 5)
    (run-instruction! #x8011)
    (expect (register-value 0) :to-be 15)))

(describe "8XY2 AND Vx, Vy"
  (it "bitwise-ANDs Vx and Vy into Vx"
    (reset-machine!)
    (set-register! 0 12)
    (set-register! 1 10)
    (run-instruction! #x8012)
    (expect (register-value 0) :to-be 8)))

(describe "8XY3 XOR Vx, Vy"
  (it "bitwise-XORs Vx and Vy into Vx"
    (reset-machine!)
    (set-register! 0 12)
    (set-register! 1 10)
    (run-instruction! #x8013)
    (expect (register-value 0) :to-be 6)))

(describe "8XY4 ADD Vx, Vy"
  (it "sets VF to 0 and the sum when it fits in a byte"
    (reset-machine!)
    (set-register! 0 10)
    (set-register! 1 20)
    (run-instruction! #x8014)
    (with-soft-assertions
      (expect (register-value 0) :to-be 30)
      (expect (register-value 15) :to-be 0)))
  (it "sets VF to 1 and wraps mod 256 on carry"
    (reset-machine!)
    (set-register! 0 200)
    (set-register! 1 100)
    (run-instruction! #x8014)
    (with-soft-assertions
      (expect (register-value 0) :to-be 44)
      (expect (register-value 15) :to-be 1))))

(describe "8XY5 SUB Vx, Vy"
  (it "sets VF to 1 (not borrow) and subtracts when Vx > Vy"
    (reset-machine!)
    (set-register! 0 10)
    (set-register! 1 3)
    (run-instruction! #x8015)
    (with-soft-assertions
      (expect (register-value 0) :to-be 7)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 and wraps mod 256 when Vx <= Vy"
    (reset-machine!)
    (set-register! 0 3)
    (set-register! 1 10)
    (run-instruction! #x8015)
    (with-soft-assertions
      (expect (register-value 0) :to-be 249)
      (expect (register-value 15) :to-be 0))))

(describe "8XY6 SHR Vx {, Vy}"
  (it "sets VF to Vx's least-significant bit and halves Vx (odd case)"
    (reset-machine!)
    (set-register! 0 181)
    (run-instruction! #x8016)
    (with-soft-assertions
      (expect (register-value 0) :to-be 90)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 and halves Vx (even case)"
    (reset-machine!)
    (set-register! 0 180)
    (run-instruction! #x8016)
    (with-soft-assertions
      (expect (register-value 0) :to-be 90)
      (expect (register-value 15) :to-be 0)))
  (it "ignores Vy (the modern quirk this stage commits to)"
    (reset-machine!)
    (set-register! 0 180)
    (set-register! 1 255)
    (run-instruction! #x8016)
    (expect (register-value 0) :to-be 90)))

(describe "8XY7 SUBN Vx, Vy"
  (it "sets VF to 1 (not borrow) and Vx = Vy - Vx when Vy > Vx"
    (reset-machine!)
    (set-register! 0 3)
    (set-register! 1 10)
    (run-instruction! #x8017)
    (with-soft-assertions
      (expect (register-value 0) :to-be 7)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 and wraps mod 256 when Vy <= Vx"
    (reset-machine!)
    (set-register! 0 10)
    (set-register! 1 3)
    (run-instruction! #x8017)
    (with-soft-assertions
      (expect (register-value 0) :to-be 249)
      (expect (register-value 15) :to-be 0))))

(describe "8XYE SHL Vx {, Vy}"
  (it "sets VF to Vx's most-significant bit and doubles Vx mod 256"
    (reset-machine!)
    (set-register! 0 192)
    (run-instruction! #x801E)
    (with-soft-assertions
      (expect (register-value 0) :to-be 128)
      (expect (register-value 15) :to-be 1)))
  (it "sets VF to 0 when the most-significant bit is clear"
    (reset-machine!)
    (set-register! 0 64)
    (run-instruction! #x801E)
    (with-soft-assertions
      (expect (register-value 0) :to-be 128)
      (expect (register-value 15) :to-be 0)))
  (it "ignores Vy (the modern quirk this stage commits to)"
    (reset-machine!)
    (set-register! 0 192)
    (set-register! 1 255)
    (run-instruction! #x801E)
    (with-soft-assertions
      (expect (register-value 0) :to-be 128)
      (expect (register-value 15) :to-be 1))))
