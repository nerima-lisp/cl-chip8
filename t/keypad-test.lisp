;;;; t/keypad-test.lisp -- the keyboard-to-hex-key mapping and the
;;;; press-and-hold approximation KEYPAD-APPLY-KEY-EVENT!/KEYPAD-STEP! drive.
(in-package #:cl-chip8/test)

(defun %character-event (char &key (kind :press))
  "Build a :CHARACTER cl-tty-kit KEY-EVENT for CHAR, :PRESS by default."
  (make-key-event :type :character :code char :kind kind))

(describe "key-event->chip8-key"
  (it "maps every key of the standard 4x4 QWERTY layout to its hex key"
    (with-soft-assertions
      (expect (key-event->chip8-key (%character-event #\1)) :to-be 1)
      (expect (key-event->chip8-key (%character-event #\2)) :to-be 2)
      (expect (key-event->chip8-key (%character-event #\3)) :to-be 3)
      (expect (key-event->chip8-key (%character-event #\4)) :to-be #xC)
      (expect (key-event->chip8-key (%character-event #\q)) :to-be 4)
      (expect (key-event->chip8-key (%character-event #\w)) :to-be 5)
      (expect (key-event->chip8-key (%character-event #\e)) :to-be 6)
      (expect (key-event->chip8-key (%character-event #\r)) :to-be #xD)
      (expect (key-event->chip8-key (%character-event #\a)) :to-be 7)
      (expect (key-event->chip8-key (%character-event #\s)) :to-be 8)
      (expect (key-event->chip8-key (%character-event #\d)) :to-be 9)
      (expect (key-event->chip8-key (%character-event #\f)) :to-be #xE)
      (expect (key-event->chip8-key (%character-event #\z)) :to-be #xA)
      (expect (key-event->chip8-key (%character-event #\x)) :to-be 0)
      (expect (key-event->chip8-key (%character-event #\c)) :to-be #xB)
      (expect (key-event->chip8-key (%character-event #\v)) :to-be #xF)))
  (it "is case-insensitive"
    (expect (key-event->chip8-key (%character-event #\Q)) :to-be 4))
  (it "returns NIL for an unmapped character"
    (expect (key-event->chip8-key (%character-event #\g)) :to-be nil))
  (it "returns NIL for a non-character event"
    (expect (key-event->chip8-key (make-key-event :type :special :code :up)) :to-be nil)))

(describe "keypad-apply-key-event!"
  (it "asserts key-down for a mapped key"
    (reset-cpu-state!)
    (keypad-reset!)
    (keypad-apply-key-event! (%character-event #\1))
    (expect (key-down-p 1) :to-be-truthy))
  (it "ignores an unmapped key"
    (reset-cpu-state!)
    (keypad-reset!)
    (keypad-apply-key-event! (%character-event #\g))
    (expect (pressed-keys) :to-be nil))
  (it "retracts key-down and clears the hold countdown on a :release event"
    (reset-cpu-state!)
    (keypad-reset!)
    (keypad-apply-key-event! (%character-event #\1))
    (expect (key-down-p 1) :to-be-truthy)
    (keypad-apply-key-event! (%character-event #\1 :kind :release))
    (expect (key-down-p 1) :to-be-falsy))
  (it "treats a release for an already-up key as idempotent"
    (reset-cpu-state!)
    (keypad-reset!)
    (keypad-apply-key-event! (%character-event #\1 :kind :release))
    (expect (key-down-p 1) :to-be-falsy)))

(describe "keypad-apply-key-events!"
  (before-each
    (reset-cpu-state!)
    (keypad-reset!))
  (it "applies every event in order and returns EVENTS"
    (let ((events (list (%character-event #\1) (%character-event #\2))))
      (expect (keypad-apply-key-events! events) :to-be events)
      (with-soft-assertions
        (expect (key-down-p 1) :to-be-truthy)
        (expect (key-down-p 2) :to-be-truthy)))))

(describe "keypad-step!"
  (before-each
    (reset-cpu-state!)
    (keypad-reset!))
  (it "retracts key-down after +key-hold-ticks+ ticks without a fresh press"
    (keypad-apply-key-event! (%character-event #\1))
    (expect (key-down-p 1) :to-be-truthy)
    (dotimes (i +key-hold-ticks+)
      (keypad-step!))
    (expect (key-down-p 1) :to-be-falsy))
  (it "keeps key-down asserted while the key keeps being pressed"
    (dotimes (i (* 2 +key-hold-ticks+))
      (keypad-apply-key-event! (%character-event #\1))
      (keypad-step!))
    (expect (key-down-p 1) :to-be-truthy)))
