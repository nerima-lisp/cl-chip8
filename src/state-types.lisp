;;;; src/state-types.lisp -- CPU state constants and storage declarations.
;;;;
;;;; State reset and query operations live in state.lisp.
(in-package #:cl-chip8)

(defvar *rulebase* (make-rulebase)
  "The mutable Prolog rulebase holding CPU state as dynamic facts.")

(defconstant +register-count+ 16
  "The number of general-purpose registers, V0 through VF.")

(defconstant +initial-pc+ +rom-load-address+
  "The program counter's value immediately after a reset: the conventional
CHIP-8 ROM load address.")

(defconstant +call-stack-limit+ 16
  "The maximum number of nested CALLs the call stack holds before CALL must
signal CHIP8-STACK-OVERFLOW. Declared alongside the state it bounds so that
the opcode guard, its condition, and this stage's fact shape agree on the same
number.")

(deftype chip8-nibble () '(unsigned-byte 4))
(deftype chip8-opcode () '(unsigned-byte 16))
(deftype chip8-register-index () '(integer 0 15))
(deftype chip8-key () '(integer 0 15))
