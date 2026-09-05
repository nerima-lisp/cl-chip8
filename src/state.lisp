;;;; CPU state is stored as dynamic facts in *RULEBASE* and manipulated with
;;;; cl-prolog-kit's ASSERTZ and RETRACTALL. This file initializes the facts;
;;;; opcode decoding and execution live in the later opcode stages.
;;;;
;;;; Fact shapes: (v Index Value), (i-register Value), (pc Value),
;;;; (call-stack List), (delay-timer Value), (sound-timer Value), and
;;;; (key-down Hex).
(in-package #:cl-chip8)

(defun reset-cpu-state! ()
  "Clear every CPU-state fact in *RULEBASE* and re-assert the initial machine
state: all +REGISTER-COUNT+ registers zeroed, I = 0, PC = +INITIAL-PC+, an
empty call stack, both timers at 0, and no keys held down. Both the real
application and tests call this to start from a clean machine. Returns
*RULEBASE*."
  (query-prolog *rulebase* '(retractall (v ?index ?value)))
  (query-prolog *rulebase* '(retractall (i-register ?value)))
  (query-prolog *rulebase* '(retractall (pc ?value)))
  (query-prolog *rulebase* '(retractall (call-stack ?value)))
  (query-prolog *rulebase* '(retractall (delay-timer ?value)))
  (query-prolog *rulebase* '(retractall (sound-timer ?value)))
  (query-prolog *rulebase* '(retractall (key-down ?key)))
  ;; ASSERTZ marks KEY-DOWN/1 dynamic; the temporary fact makes an empty
  ;; post-reset key set queryable without leaving a key asserted.
  (query-prolog *rulebase* (list 'assertz (list 'key-down -1)))
  (query-prolog *rulebase* (list 'retract (list 'key-down -1)))
  (dotimes (index +register-count+)
    (query-prolog *rulebase* (list 'assertz (list 'v index 0))))
  (query-prolog *rulebase* (list 'assertz (list 'i-register 0)))
  (query-prolog *rulebase* (list 'assertz (list 'pc +initial-pc+)))
  (query-prolog *rulebase* (list 'assertz (list 'call-stack nil)))
  (query-prolog *rulebase* (list 'assertz (list 'delay-timer 0)))
  (query-prolog *rulebase* (list 'assertz (list 'sound-timer 0)))
  *rulebase*)

(declaim (inline key-down-p))

(defun key-down-p (key)
  "Return true when hex key KEY (0-15) currently has a KEY-DOWN fact asserted
  in *RULEBASE*."
  (check-type key chip8-key)
  (prolog-succeeds-p *rulebase* (list 'key-down key)))

(defun pressed-keys ()
  "Return the list of hex keys (0-15) currently asserted as KEY-DOWN facts in
*RULEBASE*, in no particular order."
  (mapcar (lambda (solution)
            (let ((key (solution-binding '?key solution)))
              (check-type key chip8-key)
              key))
          (query-prolog *rulebase* (list 'key-down '?key))))
