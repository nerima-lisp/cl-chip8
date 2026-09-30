(in-package #:cl-chip8/test)
(describe "keypad"
  (it "tracks key transitions"
    (let ((m (make-chip8-machine)))
      (chip8-key-down! m 5) (expect (key-down-p m 5) :to-be t)
      (chip8-key-up! m 5) (expect (key-down-p m 5) :to-be nil)))
  (it "treats keys outside the CHIP-8 range as not pressed"
    (let ((m (make-chip8-machine)))
      (expect (key-down-p m -1) :to-be nil)
      (expect (key-down-p m 16) :to-be nil))))
