(in-package #:cl-chip8/test)
(describe "machine framebuffer"
  (it "clears and toggles pixels"
    (let ((m (make-chip8-machine)))
      (setf (aref (chip8-machine-framebuffer m) 5 5) 1)
      (display-reset! m)
      (expect (display-pixel-value m 5 5) :to-be 0)
      (expect (display-xor-pixel! m 5 5) :to-be nil)
      (expect (display-pixel-value m 5 5) :to-be 1))))
