;;;; src/memory-types.lisp -- memory constants and storage declarations.
;;;;
;;;; Runtime access and bounds checks live in memory.lisp.
(in-package #:cl-chip8)

(defconstant +memory-size+ 4096
  "The size, in bytes, of the CHIP-8 address space.")

(defconstant +rom-load-address+ #x200
  "The conventional CHIP-8 ROM load address. Programs assume their own code
starts here; addresses below it are reserved for the interpreter, including
the fontset (see fontset.lisp).")

(defvar *memory* (make-array +memory-size+
                              :element-type '(unsigned-byte 8)
                              :initial-element 0)
  "The full 4096-byte CHIP-8 address space, indexed 0 to 4095. A DEFVAR, not a
DEFPARAMETER: reloading this file must not silently wipe out a machine's
memory contents. Call MEMORY-RESET! to clear it explicitly.")
