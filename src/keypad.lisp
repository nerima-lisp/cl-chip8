;;;; src/keypad.lisp -- cl-tty-kit KEY-EVENTs to CHIP-8 hex keys.
;;;;
;;;; The standard 4x4 QWERTY layout this file maps against (see
;;;; docs/src/guide/terminal.md for the published copy of this table):
;;;;
;;;;   1 2 3 4      1 2 3 C
;;;;   q w e r  ->  4 5 6 D
;;;;   a s d f      7 8 9 E
;;;;   z x c v      A 0 B F
;;;;
;;;; Without kitty keyboard mode, held keys arrive as repeated :PRESS events.
;;;; Mapped presses reset a 60Hz hold countdown; KEYPAD-STEP! retracts the
;;;; KEY-DOWN fact when the countdown expires. :RELEASE is handled directly.
(in-package #:cl-chip8)

(defun keypad-reset! ()
  "Clear every pending hold countdown and return *KEY-HOLD-COUNTDOWNS*. Does
not itself retract any KEY-DOWN fact -- callers pair this with
RESET-CPU-STATE!, which already clears every KEY-DOWN fact directly."
  (clrhash *key-hold-countdowns*)
  *key-hold-countdowns*)

(defun key-event->chip8-key (event)
  "Return the CHIP-8 hex key (0-15) the cl-tty-kit KEY-EVENT EVENT maps to,
or NIL when EVENT is not a :CHARACTER event for a mapped keypad character.
Case-insensitive, so both q and Q map to key 4."
  (when (eq (key-event-type event) :character)
    (let ((key (cdr (assoc (char-downcase (key-event-code event))
                           +keypad-mapping+
                           :test #'char=))))
      (when key
        (the chip8-key key)))))

(defun keypad-apply-key-event! (event)
  "Apply one decoded cl-tty-kit KEY-EVENT to the keypad: for a mapped key,
assert its KEY-DOWN fact (if not already asserted) and (re)arm its hold
countdown. A :RELEASE event retracts KEY-DOWN immediately and clears the
countdown, precise in the (currently unreached, kitty-only) case a real
release is ever reported. Every other event -- unmapped keys, and :PRESS/
:REPEAT, handled identically per this file's header comment -- just arms the
countdown. Returns EVENT."
  (let ((key (key-event->chip8-key event)))
    (when key
      (if (eq (key-event-kind event) :release)
          (progn
            (when (key-down-p key)
              (query-prolog *rulebase* (list 'retract (list 'key-down key))))
            (remhash key *key-hold-countdowns*))
          (progn
            (unless (key-down-p key)
              (query-prolog *rulebase* (list 'assertz (list 'key-down key))))
            (setf (gethash key *key-hold-countdowns*) +key-hold-ticks+)))))
  event)

(defun keypad-apply-key-events! (events)
  "Apply KEYPAD-APPLY-KEY-EVENT! to each of EVENTS in order. Returns EVENTS."
  (dolist (event events events)
    (keypad-apply-key-event! event)))

(defun keypad-step! ()
  "Advance every currently-down key's hold countdown by one 60Hz tick,
retracting KEY-DOWN for any key whose countdown reaches zero without a fresh
press. Call once per tick, alongside STEP-TIMERS!. Returns no values."
  (dolist (key (pressed-keys))
    (let ((remaining (1- (gethash key *key-hold-countdowns* 0))))
      (if (plusp remaining)
          (setf (gethash key *key-hold-countdowns*) remaining)
          (progn
            (query-prolog *rulebase* (list 'retract (list 'key-down key)))
            (remhash key *key-hold-countdowns*)))))
  (values))
