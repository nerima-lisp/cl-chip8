(in-package #:cl-chip8/test)
(describe "timers"
  (it "decrements both timers"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-delay-timer m) 2 (chip8-machine-sound-timer m) 1)
      (step-timers! m)
      (expect (chip8-machine-delay-timer m) :to-be 1)
      (expect (chip8-machine-sound-timer m) :to-be 0))))
