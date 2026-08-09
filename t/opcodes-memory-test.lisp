;;;; t/opcodes-memory-test.lisp -- ANNN, CXKK, DXYN, FX1E, FX29, FX33, FX55,
;;;; FX65: instructions that address memory, I, or the display.
(in-package #:cl-chip8/test)

(describe "ANNN LD I, addr"
  (before-each (reset-machine!))
  (it "sets I to NNN"
    (run-instruction! #xA300)
    (expect (i-register-value) :to-be #x300)))

(describe "CXKK RND Vx, byte"
  (before-each (reset-machine!))
  (it "masks the random byte with KK, so a mask of 0 is always 0"
    (set-register! 0 255)
    (run-instruction! #xC000)
    (expect (register-value 0) :to-be 0))
  (it "never sets a bit outside KK's mask, across many draws"
    (dotimes (i 100)
      (run-instruction! #xC00F) ; mask = #x0F
      (expect (logtest (register-value 0) (lognot #x0F)) :to-be-falsy))))

(describe "DXYN DRW Vx, Vy, nibble"
  ;; Seed VF with the sentinel, not 0. RESET-MACHINE! already zeroes every
  ;; register, so a bare (expect (register-value 15) :to-be 0) after a
  ;; non-colliding draw is guaranteed by the fixture rather than by DXYN --
  ;; it passes even if DXYN never writes VF at all, which was verified by
  ;; mutation. DXYN always writes the collision flag (0 or 1), so starting
  ;; from #xAA makes every "no collision" assertion prove the write happened.
  ;; Same reasoning, and the same constant, as t/opcodes-alu-test.lisp:14.
  (before-each (reset-machine!) (set-register! 15 +vf-sentinel+))
  (it "draws a sprite byte and reports no collision on a clear pixel"
    (setf (aref *memory* #x300) #x80) ; one row, leftmost bit set
    (set-i-register! #x300)
    (set-register! 0 5)
    (set-register! 1 5)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 5 5) :to-be 1)
      (expect (register-value 15) :to-be 0)))
  (it "reports a collision when XOR-ing erases a previously set pixel"
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
    (setf (aref *memory* #x300) #xFF) ; 8 bits set
    (set-i-register! #x300)
    (set-register! 0 60) ; columns 60-67; only 60-63 are on-screen
    (set-register! 1 0)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 63 0) :to-be 1)
      (expect (register-value 15) :to-be 0)))
  (it "does not draw rows past the bottom edge either (no vertical wraparound)"
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
      (expect (register-value 15) :to-be 0)))
  ;; The sprite ORIGIN wraps modulo the display even though the BODY clips
  ;; (the two cases above). An off-screen Vx/Vy must not silently draw
  ;; nothing: DRAW-SPRITE takes Vx mod 64 and Vy mod 32 once, before the
  ;; row/bit offset is added.
  (it "wraps an origin whose Vx is past the right edge back to column 70 mod 64"
    (setf (aref *memory* #x300) #x80) ; leftmost bit set
    (set-i-register! #x300)
    (set-register! 0 70) ; 70 mod 64 = 6
    (set-register! 1 0)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 6 0) :to-be 1)
      (expect (register-value 15) :to-be 0)))
  (it "wraps an origin whose Vy is past the bottom edge back to row 40 mod 32"
    (setf (aref *memory* #x300) #x80)
    (set-i-register! #x300)
    (set-register! 0 0)
    (set-register! 1 40) ; 40 mod 32 = 8
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 0 8) :to-be 1)
      (expect (register-value 15) :to-be 0)))
  (it "wraps an origin exactly one column past the right edge back to column 0"
    (setf (aref *memory* #x300) #x80)
    (set-i-register! #x300)
    (set-register! 0 64) ; 64 mod 64 = 0
    (set-register! 1 0)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 0 0) :to-be 1)
      (expect (register-value 15) :to-be 0)))
  (it "clips the body at the right edge after wrapping the origin, rather than wrapping it too"
    ;; Vx=124 wraps to column 60, so an 8-bit row covers 60-67: columns 60-63
    ;; are drawn and 64-67 are dropped. If the BODY wrapped as well, columns
    ;; 0-3 would light up instead -- exactly what the last two assertions
    ;; reject.
    (setf (aref *memory* #x300) #xFF)
    (set-i-register! #x300)
    (set-register! 0 124)
    (set-register! 1 0)
    (run-instruction! #xD011)
    (with-soft-assertions
      (expect (display-pixel-value 60 0) :to-be 1)
      (expect (display-pixel-value 63 0) :to-be 1)
      (expect (display-pixel-value 0 0) :to-be 0)
      (expect (display-pixel-value 3 0) :to-be 0)
      (expect (register-value 15) :to-be 0)))
  (it "draws nothing and still advances PC when N is 0"
    (setf (aref *memory* #x300) #xFF)
    (set-i-register! #x300)
    (set-register! 0 0)
    (set-register! 1 0)
    (run-instruction! #xD010)
    (with-soft-assertions
      (expect (display-pixel-value 0 0) :to-be 0)
      (expect (register-value 15) :to-be 0)
      (expect (pc-value) :to-be (+ +rom-load-address+ 2)))))

(describe "FX1E ADD I, Vx"
  (before-each (reset-machine!))
  (it "adds Vx into I and leaves VF exactly as it found it"
    ;; VF is seeded nonzero on purpose. RESET-CPU-STATE! already zeroes every
    ;; register, so asserting VF = 0 after a reset would hold no matter what
    ;; FX1E did to it; only a value the instruction would have to overwrite
    ;; makes "VF untouched" a claim this test can actually fail on.
    (set-i-register! #x300)
    (set-register! 0 5)
    (set-register! 15 #xAB)
    (run-instruction! #xF01E)
    (with-soft-assertions
      (expect (i-register-value) :to-be (+ #x300 5))
      (expect (register-value 15) :to-be #xAB)))
  (it "wraps I mod 65536 (16 bits) rather than growing unbounded"
    (set-i-register! #xFFFE)
    (set-register! 0 5)
    (run-instruction! #xF01E)
    (expect (i-register-value) :to-be (mod (+ #xFFFE 5) 65536)))
  (it "wraps I back to 0 exactly at the 16-bit boundary"
    (set-i-register! #xFFFF)
    (set-register! 0 1)
    (run-instruction! #xF01E)
    (expect (i-register-value) :to-be 0)))

(describe "FX29 LD F, Vx"
  (before-each (reset-machine!))
  (it "sets I to the fontset glyph address for the hex digit in Vx"
    (set-register! 0 8)
    (run-instruction! #xF029)
    (expect (i-register-value) :to-be (+ +fontset-address+ (* 5 8))))
  ;; Vx is a full byte but the fontset is exactly 16 five-byte glyphs, so
  ;; only its low nibble names one. Both cases below must land inside
  ;; [+FONTSET-ADDRESS+, +FONTSET-ADDRESS+ + 80) -- an unmasked Vx addresses
  ;; whatever happens to sit past the fontset instead.
  (it "masks Vx to its low nibble, so Vx = 255 selects glyph F rather than address 1355"
    (set-register! 0 255)
    (run-instruction! #xF029)
    (with-soft-assertions
      (expect (i-register-value) :to-be (+ +fontset-address+ (* 5 15)))
      (expect (< (i-register-value) (+ +fontset-address+ 80)) :to-be-truthy)))
  (it "masks Vx = 16 back to glyph 0 rather than one byte past the fontset"
    (set-register! 0 16)
    (run-instruction! #xF029)
    (with-soft-assertions
      (expect (i-register-value) :to-be +fontset-address+)
      (expect (< (i-register-value) (+ +fontset-address+ 80)) :to-be-truthy))))

(describe "FX33 LD B, Vx"
  (before-each (reset-machine!))
  (it "stores the 3 BCD digits of Vx at I, I+1, I+2"
    (set-register! 0 234)
    (set-i-register! #x300)
    (run-instruction! #xF033)
    (with-soft-assertions
      (expect (aref *memory* #x300) :to-be 2)
      (expect (aref *memory* #x301) :to-be 3)
      (expect (aref *memory* #x302) :to-be 4))))

(describe "FX55 LD [I], Vx"
  (before-each (reset-machine!))
  (it "stores V0..Vx at I without changing I"
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
  (before-each (reset-machine!))
  (it "loads V0..Vx from I without changing I"
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
  (before-each (reset-machine!))
  (it "FX33 signals chip8-memory-access-out-of-bounds without partially storing BCD digits"
    (set-register! 0 255)
    (setf (aref *memory* (1- +memory-size+)) #xA5)
    (set-i-register! (1- +memory-size+))
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xF033))
    (expect (aref *memory* (1- +memory-size+)) :to-be #xA5))
  (it "FX55 signals chip8-memory-access-out-of-bounds when the register block overruns memory"
    (set-i-register! (1- +memory-size+))
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xF155))) ; stores V0..V1, 2 bytes, only 1 available at I
  (it "FX55 does not signal, and does not touch memory, when I alone (X=0) fits exactly"
    (set-register! 0 42)
    (set-i-register! (1- +memory-size+))
    (run-instruction! #xF055) ; stores just V0, 1 byte, fits at the last address
    (expect (aref *memory* (1- +memory-size+)) :to-be 42))
  (it "FX65 signals chip8-memory-access-out-of-bounds when the register block overruns memory"
    (set-i-register! (1- +memory-size+))
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xF165))) ; loads V0..V1, 2 bytes, only 1 available at I
  (it "DXYN signals chip8-memory-access-out-of-bounds when the sprite's rows overrun memory"
    (set-i-register! (1- +memory-size+))
    (set-register! 0 0)
    (set-register! 1 0)
    (signals chip8-memory-access-out-of-bounds
      (run-instruction! #xD012))) ; N=2 rows, only 1 byte available at I
  (it "DXYN does not signal for a single-row sprite that fits exactly at the last address"
    (setf (aref *memory* (1- +memory-size+)) #x80)
    (set-i-register! (1- +memory-size+))
    (set-register! 0 0)
    (set-register! 1 0)
    (run-instruction! #xD011)
    (expect (display-pixel-value 0 0) :to-be 1)))
(describe "public memory and display boundary validation"
  (before-each (reset-machine!))
  (it "rejects negative addresses and spans before array access"
    (with-soft-assertions
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access -1 1))
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access 0 -1))))
  (it "rejects a negative ROM address before touching memory"
    (signals chip8-memory-access-out-of-bounds
      (load-bytes-into-memory #(1) -1)))
  ;; No register can hold a negative value, so these two reach DRAW-SPRITE
  ;; directly rather than through an opcode. They pin the sign behavior of
  ;; the origin wrap: MOD is non-negative for a positive divisor, so a
  ;; negative coordinate lands at the far edge and never at a negative array
  ;; index.
  (it "wraps a sprite origin left of the display to the rightmost column"
    (setf (aref *memory* #x300) #x80)
    (let* ((solutions
             (query-prolog *rulebase*
                           (list 'draw-sprite #x300 -1 0 1 '?collision)))
           (solution (first solutions)))
      (with-soft-assertions
        (expect solution :to-be-truthy)
        (when solution
          (expect (solution-binding '?collision solution) :to-be 0)
          (expect (display-pixel-value 63 0) :to-be 1)
          (expect (display-pixel-value 0 0) :to-be 0)))))
  (it "wraps a sprite origin above the display to the bottommost row"
    (setf (aref *memory* #x300) #x80)
    (let* ((solutions
             (query-prolog *rulebase*
                           (list 'draw-sprite #x300 0 -1 1 '?collision)))
           (solution (first solutions)))
      (with-soft-assertions
        (expect solution :to-be-truthy)
        (when solution
          (expect (solution-binding '?collision solution) :to-be 0)
          (expect (display-pixel-value 0 31) :to-be 1)
          (expect (display-pixel-value 0 0) :to-be 0))))))
