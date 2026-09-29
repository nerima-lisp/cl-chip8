(in-package #:cl-chip8/test)
(describe "fontset"
  (it "loads the standard glyph bytes"
    (let ((m (make-chip8-machine)))
      (expect (memory-read m +fontset-address+) :to-be #xf0)
      (expect (memory-read m (+ +fontset-address+ 79)) :to-be #x80))))
