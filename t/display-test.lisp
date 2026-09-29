(in-package #:cl-chip8/test)
(describe "machine framebuffer"
  (it "clears and toggles pixels"
    (let ((m (make-chip8-machine)))
      (setf (aref (chip8-machine-framebuffer m) 5 5) 1)
      (display-reset! m)
      (expect (display-pixel-value m 5 5) :to-be 0)
      (expect (display-xor-pixel! m 5 5) :to-be nil)
      (expect (display-pixel-value m 5 5) :to-be 1)))

  (it "wraps an off-screen sprite origin before clipping"
    (let ((m (make-chip8-machine :quirks (make-chip8-quirks :clipping :clip))))
      (load-bytes-into-memory m #(240) #x300)
      (load-bytes-into-memory m #(208 17) #x200)
      (setf (chip8-machine-i m) #x300
            (chip8-machine-register m 0) 66
            (chip8-machine-register m 1) 0)
      (execute-instruction! m)
      (expect (loop for x from 2 below 6 always (= (display-pixel-value m x 0) 1))
              :to-be-truthy)))

  (it-each ((:clip nil) (:wrap t))
    "clips or wraps the pixels beyond the right edge under ~A"
    (clipping wraps-p)
    (let ((m (make-chip8-machine :quirks (make-chip8-quirks :clipping clipping))))
      (load-bytes-into-memory m #(255) #x300)
      (load-bytes-into-memory m #(208 17) #x200)
      (setf (chip8-machine-i m) #x300
            (chip8-machine-register m 0) 60
            (chip8-machine-register m 1) 0)
      (execute-instruction! m)
      (expect (loop for x from 60 below 64 always (= (display-pixel-value m x 0) 1))
              :to-be-truthy)
      (expect (loop for x from 0 below 4 always (= (display-pixel-value m x 0)
                                                    (if wraps-p 1 0)))
              :to-be-truthy))))
