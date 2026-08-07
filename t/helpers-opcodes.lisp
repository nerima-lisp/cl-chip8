;;;; t/helpers-opcodes.lisp -- shared helpers for the opcode/integration
;;;; tests. Named per CODING_STANDARD.md's helpers-<concern>.lisp convention
;;;; for shared test-helper files, not <concern>-test.lisp (which is reserved
;;;; for a file that itself defines DESCRIBE/IT specs).
;;;;
;;;; Every opcode test follows the same shape: reset the machine, poke a
;;;; small hand-authored byte sequence into memory (and sometimes a register
;;;; precondition), run one or more instructions via EXECUTE-INSTRUCTION!,
;;;; and assert on the resulting register/PC/I/memory/display state. These
;;;; helpers read and write CPU-state facts directly against *RULEBASE*
;;;; (via the test-only ASSERTZ/RETRACT/QUERY-PROLOG imports in package.lisp)
;;;; so each test file can stay focused on the opcode it exercises rather
;;;; than on repeating this plumbing.
(in-package #:cl-chip8/test)

(defun reset-machine! ()
  "Reset CPU state, memory, and the display to a clean starting point, the
precondition every opcode test starts from."
  (reset-cpu-state!)
  (memory-reset!)
  (display-reset!))

(defun register-value (index)
  "Return register INDEX's current value."
  (solution-binding '?value (first (query-prolog *rulebase* (list 'v index '?value)))))

(defun set-register! (index value)
  "Set register INDEX to VALUE, retracting whatever it currently holds."
  (let ((current (register-value index)))
    (query-prolog *rulebase* (list 'retract (list 'v index current))))
  (query-prolog *rulebase* (list 'assertz (list 'v index value))))

(defun i-register-value ()
  "Return the current value of the I register."
  (solution-binding '?value (first (query-prolog *rulebase* '(i-register ?value)))))

(defun set-i-register! (value)
  "Set the I register to VALUE."
  (let ((current (i-register-value)))
    (query-prolog *rulebase* (list 'retract (list 'i-register current))))
  (query-prolog *rulebase* (list 'assertz (list 'i-register value))))

(defun pc-value ()
  "Return the current program counter."
  (solution-binding '?value (first (query-prolog *rulebase* '(pc ?value)))))

(defun set-pc! (value)
  "Set the program counter to VALUE."
  (let ((current (pc-value)))
    (query-prolog *rulebase* (list 'retract (list 'pc current))))
  (query-prolog *rulebase* (list 'assertz (list 'pc value))))

(defun call-stack-value ()
  "Return the current call-stack list."
  (solution-binding '?value (first (query-prolog *rulebase* '(call-stack ?value)))))

(defun delay-timer-value ()
  (solution-binding '?value (first (query-prolog *rulebase* '(delay-timer ?value)))))

(defun set-delay-timer! (value)
  (let ((current (delay-timer-value)))
    (query-prolog *rulebase* (list 'retract (list 'delay-timer current))))
  (query-prolog *rulebase* (list 'assertz (list 'delay-timer value))))

(defun sound-timer-value ()
  (solution-binding '?value (first (query-prolog *rulebase* '(sound-timer ?value)))))

(defun set-sound-timer! (value)
  (let ((current (sound-timer-value)))
    (query-prolog *rulebase* (list 'retract (list 'sound-timer current))))
  (query-prolog *rulebase* (list 'assertz (list 'sound-timer value))))

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
