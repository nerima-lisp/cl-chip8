(in-package #:cl-chip8/test)

(describe "reset-cpu-state!"
  (before-each
    (reset-cpu-state!))
  (it "zeroes every one of the 16 registers"
    (with-soft-assertions
      (dotimes (index +register-count+)
        (let ((solutions (query-prolog *rulebase* (list 'v index '?value))))
          (expect (solution-binding '?value (first solutions)) :to-be 0)))))
  (it "sets the program counter to +initial-pc+"
    (let ((solutions (query-prolog *rulebase* '(pc ?value))))
      (expect (solution-binding '?value (first solutions)) :to-be +initial-pc+)))
  (it "sets the I register to 0"
    (let ((solutions (query-prolog *rulebase* '(i-register ?value))))
      (expect (solution-binding '?value (first solutions)) :to-be 0)))
  (it "sets an empty call stack"
    (let ((solutions (query-prolog *rulebase* '(call-stack ?value))))
      (expect (solution-binding '?value (first solutions)) :to-be nil)))
  (it "zeroes both timers"
    (with-soft-assertions
      (expect (solution-binding '?value (first (query-prolog *rulebase* '(delay-timer ?value))))
              :to-be 0)
      (expect (solution-binding '?value (first (query-prolog *rulebase* '(sound-timer ?value))))
              :to-be 0)))
  (it "starts with no keys held down"
    (expect (pressed-keys) :to-be nil))
  (it "leaves exactly one fact per register after two resets, not a stale duplicate"
    (reset-cpu-state!)
    (expect (length (query-prolog *rulebase* (list 'v 0 '?value))) :to-be 1)))

(describe "asserting and retracting a register fact directly against *rulebase*"
  (before-each
    (reset-cpu-state!))
  (it "round-trips a fact through assertz, query-prolog, and retract"
    ;; RESET-CPU-STATE! already asserted (v 0 0); retract it first so this
    ;; test's own fact is the only one query-prolog can find afterwards.
    (query-prolog *rulebase* (list 'retract (list 'v 0 0)))
    (query-prolog *rulebase* (list 'assertz (list 'v 0 5)))
    (let ((solutions (query-prolog *rulebase* (list 'v 0 '?value))))
      (expect (solution-binding '?value (first solutions)) :to-be 5))
    (query-prolog *rulebase* (list 'retract (list 'v 0 5)))
    (expect (query-prolog *rulebase* (list 'v 0 '?value)) :to-be nil)))

(describe "key-down-p and pressed-keys"
  (before-each
    (reset-cpu-state!))
  (it "reports a key as not pressed when no fact is asserted"
    (expect (key-down-p 5) :to-be-falsy))
  (it "reports a key as pressed once its fact is asserted, and lists it"
    (query-prolog *rulebase* (list 'assertz (list 'key-down 5)))
    (with-soft-assertions
      (expect (key-down-p 5) :to-be-truthy)
      (expect (pressed-keys) :to-equal '(5)))
    (query-prolog *rulebase* (list 'retract (list 'key-down 5)))
    (expect (key-down-p 5) :to-be-falsy)))
