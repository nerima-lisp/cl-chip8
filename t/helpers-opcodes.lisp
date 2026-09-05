;;;; Shared helpers for opcode and integration tests.
(in-package #:cl-chip8/test)

(defun reset-machine! ()
  "Reset CPU state, memory, and the display to a clean starting point, the
precondition every opcode test starts from."
  (reset-cpu-state!)
  (memory-reset!)
  (display-reset!))

(defmacro define-fact-accessor! (name functor)
  "Define NAME-VALUE to return FUNCTOR's current single-argument value in
*RULEBASE*, and SET-NAME! to retract that value and assertz VALUE in its
place. FUNCTOR is a CPU-state fact functor holding exactly one argument --
I-REGISTER, PC, DELAY-TIMER, or SOUND-TIMER (see state.lisp's fact shapes).
Every single-value accessor pair below shares this exact retract-then-assertz
shape, so this is its one declarative definition point instead of four
hand-copied repetitions of it."
  (let ((getter (intern (format nil "~A-VALUE" name)))
        (setter (intern (format nil "SET-~A!" name))))
    `(progn
       (defun ,getter ()
         (solution-binding '?value (first (query-prolog *rulebase* (list ',functor '?value)))))
       (defun ,setter (value)
         (let ((current (,getter)))
           (query-prolog *rulebase* (list 'retract (list ',functor current))))
         (query-prolog *rulebase* (list 'assertz (list ',functor value)))))))

(defmacro define-indexed-fact-accessor! (name functor)
  "Like DEFINE-FACT-ACCESSOR!, but for a FUNCTOR whose fact takes an INDEX
before its value, like V (the 16 general registers)."
  (let ((getter (intern (format nil "~A-VALUE" name)))
        (setter (intern (format nil "SET-~A!" name))))
    `(progn
       (defun ,getter (index)
         (solution-binding '?value (first (query-prolog *rulebase* (list ',functor index '?value)))))
       (defun ,setter (index value)
         (let ((current (,getter index)))
           (query-prolog *rulebase* (list 'retract (list ',functor index current))))
         (query-prolog *rulebase* (list 'assertz (list ',functor index value)))))))

(define-indexed-fact-accessor! register v)
(define-fact-accessor! i-register i-register)
(define-fact-accessor! pc pc)
(define-fact-accessor! delay-timer delay-timer)
(define-fact-accessor! sound-timer sound-timer)

(defun call-stack-value ()
  "Return the current call-stack list. Read-only: no opcode test needs to
force a specific call-stack precondition, only CALL/RET's own execution
mutates it, so this file defines no SET-CALL-STACK! to match."
  (solution-binding '?value (first (query-prolog *rulebase* '(call-stack ?value)))))

(defun load-instruction! (opcode &optional (address +rom-load-address+))
  "Load the 16-bit OPCODE as two big-endian bytes at ADDRESS (default
+ROM-LOAD-ADDRESS+, where PC starts after RESET-CPU-STATE!). Returns no
values."
  (load-bytes-into-memory
   (make-array 2 :element-type '(unsigned-byte 8)
               :initial-contents (list (ldb (byte 8 8) opcode) (ldb (byte 8 0) opcode)))
   address)
  (values))

(defun run-instruction! (opcode &optional (address +rom-load-address+))
  "Reset nothing (callers set up preconditions first); load OPCODE at ADDRESS,
set PC to ADDRESS, and execute exactly one instruction via
EXECUTE-INSTRUCTION!. Returns no values."
  (load-instruction! opcode address)
  (set-pc! address)
  (execute-instruction!)
  (values))
