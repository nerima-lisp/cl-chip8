;;;; t/opcodes-memory-test.lisp -- ANNN, CXKK, DXYN, FX1E, FX29, FX33, FX55,
;;;; FX65: instructions that address memory, I, or the display.
(in-package #:cl-chip8/test)

(describe "ANNN LD I, addr"
  (it "sets I to NNN"
    (reset-machine!)
    (run-instruction! #xA300)
    (expect (i-register-value) :to-be #x300)))

(describe "CXKK RND Vx, byte"
  (it "masks the random byte with KK, so a mask of 0 is always 0"
    (reset-machine!)
    (set-register! 0 255)
    (run-instruction! #xC000)
    (expect (register-value 0) :to-be 0))
  (it "never sets a bit outside KK's mask, across many draws"
    (reset-machine!)
    (dotimes (i 100)
      (run-instruction! #xC00F) ; mask = #x0F
      (expect (logtest (register-value 0) (lognot #x0F)) :to-be-falsy))))

(describe "DXYN DRW Vx, Vy, nibble"
  (it "draws a sprite byte and reports no collision on a clear pixel"
    (reset-machine!)
    (setf (aref *memory* #x300) #x80) ; one row, leftmost bit set
    (set-i-register! #x300)
    (set-register! 0 5)
    (set-register! 1 5)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 5 5) :to-be 1)
      (expect (register-value 15) :to-be 0)))
  (it "reports a collision when XOR-ing erases a previously set pixel"
    (reset-machine!)
    (setf (aref *memory* #x300) #x80)
    (set-i-register! #x300)
    (set-register! 0 5)
    (set-register! 1 5)
    (run-instruction! #xD011)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 5 5) :to-be 0)
      (expect (register-value 15) :to-be 1)))
  (it "does not draw pixels outside the 64x32 field (no wraparound)"
    (reset-machine!)
    (setf (aref *memory* #x300) #xFF) ; 8 bits set
    (set-i-register! #x300)
    (set-register! 0 60) ; columns 60-67; only 60-63 are on-screen
    (set-register! 1 0)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 63 0) :to-be 1)
      (expect (register-value 15) :to-be 0)))
  (it "does not draw rows past the bottom edge either (no vertical wraparound)"
    (reset-machine!)
    ;; A 4-row sprite starting at y=30: rows land on 30, 31, 32, 33. Only
    ;; y=30 and y=31 are on-screen; rows 32/33 must be silently dropped, not
    ;; wrapped back to y=0/y=1.
    (setf (aref *memory* #x300) #x80)
    (setf (aref *memory* #x301) #x80)
    (setf (aref *memory* #x302) #x80)
    (setf (aref *memory* #x303) #x80)
    (set-i-register! #x300)
    (set-register! 0 0)
    (set-register! 1 30)
    (run-instruction! #xD014)
    (with-soft-assertions
      (expect (display-pixel-value 0 30) :to-be 1)
      (expect (display-pixel-value 0 31) :to-be 1)
      (expect (display-pixel-value 0 0) :to-be 0)
      (expect (display-pixel-value 0 1) :to-be 0)
      (expect (register-value 15) :to-be 0))))

(describe "FX1E ADD I, Vx"
  (it "adds Vx into I without setting VF"
    (reset-machine!)
    (set-i-register! #x300)
    (set-register! 0 5)
    (run-instruction! #xF01E)
    (with-soft-assertions
      (expect (i-register-value) :to-be (+ #x300 5))
      (expect (register-value 15) :to-be 0)))
  (it "wraps I mod 65536 (16 bits) rather than growing unbounded"
    (reset-machine!)
    (set-i-register! #xFFFE)
    (set-register! 0 5)
    (run-instruction! #xF01E)
    (expect (i-register-value) :to-be (mod (+ #xFFFE 5) 65536)))
  (it "wraps I back to 0 exactly at the 16-bit boundary"
    (reset-machine!)
    (set-i-register! #xFFFF)
    (set-register! 0 1)
    (run-instruction! #xF01E)
    (expect (i-register-value) :to-be 0)))

(describe "FX29 LD F, Vx"
  (it "sets I to the fontset glyph address for the hex digit in Vx"
    (reset-machine!)
    (set-register! 0 8)
    (run-instruction! #xF029)
    (expect (i-register-value) :to-be (+ +fontset-address+ (* 5 8)))))

(describe "FX33 LD B, Vx"
  (it "stores the 3 BCD digits of Vx at I, I+1, I+2"
    (reset-machine!)
    (set-register! 0 234)
    (set-i-register! #x300)
    (run-instruction! #xF033)
    (with-soft-assertions
      (expect (aref *memory* #x300) :to-be 2)
      (expect (aref *memory* #x301) :to-be 3)
      (expect (aref *memory* #x302) :to-be 4))))

(describe "FX55 LD [I], Vx"
  (it "stores V0..Vx at I without changing I"
    (reset-machine!)
    (set-register! 0 10)
    (set-register! 1 20)
    (set-register! 2 30)
    (set-i-register! #x300)
    (run-instruction! #xF255)
    (with-soft-assertions
      (expect (aref *memory* #x300) :to-be 10)
      (expect (aref *memory* #x301) :to-be 20)
      (expect (aref *memory* #x302) :to-be 30)
      (expect (i-register-value) :to-be #x300))))

(describe "FX65 LD Vx, [I]"
  (it "loads V0..Vx from I without changing I"
    (reset-machine!)
    (setf (aref *memory* #x300) 10)
    (setf (aref *memory* #x301) 20)
    (setf (aref *memory* #x302) 30)
    (set-i-register! #x300)
    (run-instruction! #xF265)
    (with-soft-assertions
      (expect (register-value 0) :to-be 10)
      (expect (register-value 1) :to-be 20)
      (expect (register-value 2) :to-be 30)
      (expect (i-register-value) :to-be #x300))))

(describe "memory bounds checking near the top of the address space (security review)"
  ;; +MEMORY-SIZE+ is 4096, so (1- +memory-size+) = 4095 is the last valid
  ;; address; any of these opcodes reading/writing more than 1 byte starting
  ;; there runs off the end. Each case would previously have hit an
  ;; unchecked, implementation-defined AREF failure instead of the
  ;; documented CHIP8-MEMORY-ACCESS-OUT-OF-BOUNDS condition.
  (it "FX33 signals chip8-memory-access-out-of-bounds when I+2 (the ones digit) overruns memory"
    (reset-machine!)
    (set-register! 0 255)
    (set-i-register! (1- +memory-size+))
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xF033)))
  (it "FX55 signals chip8-memory-access-out-of-bounds when the register block overruns memory"
    (reset-machine!)
    (set-i-register! (1- +memory-size+))
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xF155))) ; stores V0..V1, 2 bytes, only 1 available at I
  (it "FX55 does not signal, and does not touch memory, when I alone (X=0) fits exactly"
    (reset-machine!)
    (set-register! 0 42)
    (set-i-register! (1- +memory-size+))
    (run-instruction! #xF055) ; stores just V0, 1 byte, fits at the last address
    (expect (aref *memory* (1- +memory-size+)) :to-be 42))
  (it "FX65 signals chip8-memory-access-out-of-bounds when the register block overruns memory"
    (reset-machine!)
    (set-i-register! (1- +memory-size+))
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xF165))) ; loads V0..V1, 2 bytes, only 1 available at I
  (it "DXYN signals chip8-memory-access-out-of-bounds when the sprite's rows overrun memory"
    (reset-machine!)
    (set-i-register! (1- +memory-size+))
    (set-register! 0 0)
    (set-register! 1 0)
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xD012))) ; N=2 rows, only 1 byte available at I
  (it "DXYN does not signal for a single-row sprite that fits exactly at the last address"
    (reset-machine!)
    (setf (aref *memory* (1- +memory-size+)) #x80)
    (set-i-register! (1- +memory-size+))
    (set-register! 0 0)
    (set-register! 1 0)
    (run-instruction! #xD011)
    (expect (display-pixel-value 0 0) :to-be 1)))
