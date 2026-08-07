;;;; src/keypad.lisp -- cl-tty-kit KEY-EVENTs to CHIP-8 hex keys.
;;;;
;;;; The standard 4x4 QWERTY layout this file maps against (see the README's
;;;; own copy of this table):
;;;;
;;;;   1 2 3 4      1 2 3 C
;;;;   q w e r  ->  4 5 6 D
;;;;   a s d f      7 8 9 E
;;;;   z x c v      A 0 B F
;;;;
;;;; Press/hold approximation: cl-tty-kit's KEY-EVENT-KIND is :PRESS,
;;;; :REPEAT, or :RELEASE, but "terminals report :REPEAT and :RELEASE only
;;;; under the kitty keyboard protocol; otherwise every event is :PRESS" (see
;;;; cl-tty-kit's keys.lisp). This application does not enable the kitty
;;;; keyboard enhancements (see app.lisp), so in practice every decoded event
;;;; for a held key is a fresh :PRESS -- a real keyboard's OS-level key-repeat
;;;; delivers a steady stream of them for as long as the key stays down, and
;;;; nothing at all once it's released. There is therefore no direct signal
;;;; for "the key was just released" to retract a KEY-DOWN fact on.
;;;;
;;;; The approximation: every mapped :PRESS (or :REPEAT, handled identically
;;;; in case kitty mode is ever enabled later) asserts KEY-DOWN and resets
;;;; that key's hold countdown to +KEY-HOLD-TICKS+ 60Hz ticks. KEYPAD-STEP!,
;;;; called once per tick from the main loop alongside the timers, counts
;;;; every currently-down key's countdown toward zero and retracts KEY-DOWN
;;;; once it expires. A key genuinely held down keeps re-arming its
;;;; countdown via repeated :PRESS events faster than it can expire; a key
;;;; that was tapped once and released goes quiet, and its KEY-DOWN fact
;;;; disappears +KEY-HOLD-TICKS+ ticks later. A real :RELEASE event (should
;;;; kitty mode ever be enabled) is handled precisely instead of by timeout.
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
  (and (eq (key-event-type event) :character)
       (cdr (assoc (char-downcase (key-event-code event)) +keypad-mapping+ :test #'char=))))

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
