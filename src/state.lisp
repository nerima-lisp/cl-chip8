;;;; src/state.lisp -- the CPU state core: a Prolog rulebase of dynamic facts.
;;;;
;;;; This is the architecture's central, deliberate choice: registers, the I
;;;; register, the program counter, the call stack, and both timers are not a
;;;; Lisp struct mutated in place. They are facts in *RULEBASE*, asserted and
;;;; retracted via cl-prolog-kit's ASSERTZ/RETRACTALL builtins, which mutate the
;;;; rulebase destructively (see cl-prolog-kit's src/builtins/dynamic.lisp) -- so
;;;; one rulebase instance, built once with MAKE-RULEBASE below, is the
;;;; machine's state for its entire lifetime. A later stage drives opcode
;;;; execution by resolving Prolog goals against this same rulebase; nothing
;;;; here decodes or executes an opcode.
;;;;
;;;; Fact shapes (see also the summary in package.lisp's export list):
;;;;   (v Index Value)      -- Index in [0,15] is a register number (V0-VF),
;;;;                            Value its current byte.
;;;;   (i-register Value)   -- the 16-bit I register.
;;;;   (pc Value)           -- the program counter.
;;;;   (call-stack List)    -- the CALL/RET return-address stack as a single
;;;;                            fact holding a Lisp list, most recent call
;;;;                            first, rather than one fact per frame: a
;;;;                            16-level-max stack is small enough that a
;;;;                            list is simpler to push/pop atomically than
;;;;                            coordinating a set of per-level facts would
;;;;                            be, and CALL/RET (both later-stage opcodes)
;;;;                            only ever need the top of it.
;;;;   (delay-timer Value)  -- 0-255, decremented at 60Hz by a later stage.
;;;;   (sound-timer Value)  -- 0-255, likewise.
;;;;   (key-down Hex)       -- zero or more facts, one per hex key (0-15)
;;;;                            currently held down. A later stage asserts
;;;;                            and retracts these from real keyboard input;
;;;;                            KEY-DOWN-P and PRESSED-KEYS below are the
;;;;                            query helpers it drives them through.
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
  ;; RETRACTALL never marks a predicate dynamic -- only ASSERTA/ASSERTZ do
  ;; (see cl-prolog-kit's src/builtins/dynamic.lisp) -- and every other fact
  ;; functor above gets at least one ASSERTZ a few lines down, which marks
  ;; it dynamic as a side effect. KEY-DOWN/1 is different: "no keys held
  ;; down" is its normal post-reset state, so it would otherwise stay
  ;; completely undeclared (no property, no clauses) and PRESSED-KEYS'
  ;; query would signal an ISO existence_error instead of simply finding no
  ;; solutions. Assert a sentinel fact and retract it immediately: the
  ;; assertion marks the predicate dynamic (a permanent property, not tied
  ;; to clause count -- retraction does not clear it), and the retraction
  ;; leaves zero facts, exactly the state a fresh machine should report.
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

(defun key-down-p (key)
  "Return true when hex key KEY (0-15) currently has a KEY-DOWN fact asserted
in *RULEBASE*."
  (prolog-succeeds-p *rulebase* (list 'key-down key)))

(defun pressed-keys ()
  "Return the list of hex keys (0-15) currently asserted as KEY-DOWN facts in
*RULEBASE*, in no particular order."
  (mapcar (lambda (solution) (solution-binding '?key solution))
          (query-prolog *rulebase* (list 'key-down '?key))))
