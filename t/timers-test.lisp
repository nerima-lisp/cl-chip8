;;;; t/timers-test.lisp -- STEP-TIMERS!, the 60Hz delay/sound timer step.
(in-package #:cl-chip8/test)

(describe "step-timers!"
  (before-each
    (reset-machine!))
  (it "decrements both timers by 1"
    (set-delay-timer! 10)
    (set-sound-timer! 5)
    (step-timers!)
    (with-soft-assertions
      (expect (delay-timer-value) :to-be 9)
      (expect (sound-timer-value) :to-be 4)))
  (it "floors at 0 and does not go negative"
    (set-delay-timer! 0)
    (set-sound-timer! 0)
    (step-timers!)
    (with-soft-assertions
      (expect (delay-timer-value) :to-be 0)
      (expect (sound-timer-value) :to-be 0)))
  (it "steps independently of how many CPU instructions ran"
    (set-delay-timer! 1)
    (step-timers!)
    (expect (delay-timer-value) :to-be 0)))
