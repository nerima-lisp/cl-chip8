;;;; src/keypad-types.lisp -- keypad mapping and hold-state declarations.
;;;;
;;;; Event application and countdown logic live in keypad.lisp.
(in-package #:cl-chip8)

(defparameter +keypad-mapping+
  '((#\1 . 1) (#\2 . 2) (#\3 . 3) (#\4 . #xC)
    (#\q . 4) (#\w . 5) (#\e . 6) (#\r . #xD)
    (#\a . 7) (#\s . 8) (#\d . 9) (#\f . #xE)
    (#\z . #xA) (#\x . 0) (#\c . #xB) (#\v . #xF))
  "Maps a lowercase keyboard character to its CHIP-8 hex key (0-15), the
standard 4x4 QWERTY layout documented in the README and this file's header.")

(defparameter +key-hold-ticks+ 5
  "The number of 60Hz ticks a KEY-DOWN fact survives after its most recent
:PRESS/:REPEAT event before KEYPAD-STEP! retracts it, approximating key
release -- see this file's header comment.")

(defvar *key-hold-countdowns* (make-hash-table)
  "Maps a currently-down CHIP-8 hex key to its remaining hold countdown in
60Hz ticks. A DEFVAR, not a DEFPARAMETER, matching *RULEBASE*/*MEMORY*/
*DISPLAY*'s own reload-safety rationale: reloading this file must not wipe
out a machine already in the middle of a run. Call KEYPAD-RESET! to clear it
explicitly.")
