;;;; src/state-types.lisp -- CPU state constants and storage declarations.
;;;;
;;;; State reset and query operations live in state.lisp.
(in-package #:cl-chip8)

(defvar *rulebase* (make-rulebase)
  "The mutable Prolog rulebase holding the entire CPU state as dynamic facts
-- see this file's header comment for the fact shapes. A DEFVAR, not a
DEFPARAMETER: reloading this file must not hand a running machine a fresh,
empty rulebase out from under it. Call RESET-CPU-STATE! to reinitialize its
contents in place.")

(defconstant +register-count+ 16
  "The number of general-purpose registers, V0 through VF.")

(defconstant +initial-pc+ +rom-load-address+
  "The program counter's value immediately after a reset: the conventional
CHIP-8 ROM load address.")

(defconstant +call-stack-limit+ 16
  "The maximum number of nested CALLs the call stack holds before CALL must
signal CHIP8-STACK-OVERFLOW. Not enforced here -- CALL is an opcode a later
stage implements -- but declared alongside the state it bounds so that
stage's condition and this stage's fact shape agree on the same number.")
