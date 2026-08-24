;;;; src/timers.lisp -- 60Hz delay/sound timer stepping.
;;;;
;;;; CHIP-8's delay and sound timers decrement at a fixed 60Hz regardless of
;;;; how fast the CPU itself executes instructions -- see the brief's clock
;;;; design: the realtime tick loop's frame interval is pinned at 1/60, and
;;;; STEP-TIMERS! is called exactly once per tick from there (app.lisp),
;;;; independent of how many CPU instructions that same tick ran.
(in-package #:cl-chip8)

(declaim (inline %decrement-timer-fact!))

(defun %decrement-timer-fact! (functor)
  "Decrement the single-fact timer predicate FUNCTOR (DELAY-TIMER or
  SOUND-TIMER, passed as a plain symbol) by 1, floored at 0."
  (let* ((solution (query-prolog-first *rulebase* (list functor '?value)))
         (value (solution-binding '?value solution)))
    (check-type value chip8-octet)
    (when (plusp value)
      (query-prolog *rulebase* (list 'retract (list functor value)))
      (query-prolog *rulebase* (list 'assertz (list functor (1- value)))))))

(defun step-timers! ()
  "Decrement DELAY-TIMER and SOUND-TIMER by 1 each, floored at 0. Call once
per 60Hz tick. Returns no values."
  (%decrement-timer-fact! 'delay-timer)
  (%decrement-timer-fact! 'sound-timer)
  (values))
