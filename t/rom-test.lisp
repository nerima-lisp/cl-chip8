(in-package #:cl-chip8/test)
(describe "ROM loading"
  (it "loads bytes at the program address"
    (let ((m (make-chip8-machine)))
      (load-rom m #(1 2 3))
      (expect (memory-read m +rom-load-address+) :to-be 1)
      (expect (memory-read m (+ +rom-load-address+ 2)) :to-be 3)))
  (it "rejects an oversized ROM"
    (let ((m (make-chip8-machine)))
      (signals chip8-rom-too-large
        (load-rom m (make-array 3585 :element-type '(unsigned-byte 8)))))))
