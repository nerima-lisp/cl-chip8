(in-package #:cl-chip8/test)
(describe "keypad"
  (it "tracks key transitions"
    (let ((m (make-chip8-machine)))
      (chip8-key-down! m 5) (expect (key-down-p m 5) :to-be t)
      (chip8-key-up! m 5) (expect (key-down-p m 5) :to-be nil))))
