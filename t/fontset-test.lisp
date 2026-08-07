(in-package #:cl-chip8/test)

(describe "+chip8-fontset+"
  (it "is 80 bytes total: 16 glyphs of 5 bytes each"
    (expect (length +chip8-fontset+) :to-be 80)))

(describe "load-fontset-into-memory!"
  (it "places glyph 0 (F0 90 90 90 F0) at +fontset-address+"
    (memory-reset!)
    (load-fontset-into-memory!)
    (with-soft-assertions
      (expect (aref *memory* (+ +fontset-address+ 0)) :to-be #xF0)
      (expect (aref *memory* (+ +fontset-address+ 1)) :to-be #x90)
      (expect (aref *memory* (+ +fontset-address+ 2)) :to-be #x90)
      (expect (aref *memory* (+ +fontset-address+ 3)) :to-be #x90)
      (expect (aref *memory* (+ +fontset-address+ 4)) :to-be #xF0)))
  (it "places glyph F, index 15, (F0 80 F0 80 80) at +fontset-address+ + 75"
    (memory-reset!)
    (load-fontset-into-memory!)
    (let ((base (+ +fontset-address+ (* 15 5))))
      (with-soft-assertions
        (expect (aref *memory* (+ base 0)) :to-be #xF0)
        (expect (aref *memory* (+ base 1)) :to-be #x80)
        (expect (aref *memory* (+ base 2)) :to-be #xF0)
        (expect (aref *memory* (+ base 3)) :to-be #x80)
        (expect (aref *memory* (+ base 4)) :to-be #x80))))
  (it "places glyph 8, index 8, (F0 90 F0 90 F0) at +fontset-address+ + 40"
    (memory-reset!)
    (load-fontset-into-memory!)
    (let ((base (+ +fontset-address+ (* 8 5))))
      (with-soft-assertions
        (expect (aref *memory* (+ base 0)) :to-be #xF0)
        (expect (aref *memory* (+ base 1)) :to-be #x90)
        (expect (aref *memory* (+ base 2)) :to-be #xF0)
        (expect (aref *memory* (+ base 3)) :to-be #x90)
        (expect (aref *memory* (+ base 4)) :to-be #xF0)))))
