;;;; src/fontset.lisp -- the built-in CHIP-8 hex-digit fontset.
;;;;
;;;; These 80 bytes (16 glyphs of 5 bytes each, one row per byte, the glyph's
;;;; four most-significant bits per row lit) are fixed public-spec data that
;;;; appears in essentially every CHIP-8 implementation and reference
;;;; document, not code borrowed from any one of them.
(in-package #:cl-chip8)

(defconstant +fontset-address+ #x50
  "The conventional placement for the built-in fontset, low enough to never
collide with +ROM-LOAD-ADDRESS+ (0x200).")

;; A DEFPARAMETER, not a DEFCONSTANT: re-evaluating a DEFCONSTANT of an array
;; is only well-defined when the new value is EQL to the old one, and two
;; separately-constructed arrays with the same contents are never EQL. A
;; DEFPARAMETER re-evaluates cleanly on every reload, which is all a 16-glyph
;; lookup table needs -- it is read, never mutated.
(defparameter +chip8-fontset+
  (make-array
   80 :element-type '(unsigned-byte 8)
   :initial-contents
   '(#xF0 #x90 #x90 #x90 #xF0   ; 0
     #x20 #x60 #x20 #x20 #x70   ; 1
     #xF0 #x10 #xF0 #x80 #xF0   ; 2
     #xF0 #x10 #xF0 #x10 #xF0   ; 3
     #x90 #x90 #xF0 #x10 #x10   ; 4
     #xF0 #x80 #xF0 #x10 #xF0   ; 5
     #xF0 #x80 #xF0 #x90 #xF0   ; 6
     #xF0 #x10 #x20 #x40 #x40   ; 7
     #xF0 #x90 #xF0 #x90 #xF0   ; 8
     #xF0 #x90 #xF0 #x10 #xF0   ; 9
     #xF0 #x90 #xF0 #x90 #x90   ; A
     #xE0 #x90 #xE0 #x90 #xE0   ; B
     #xF0 #x80 #x80 #x80 #xF0   ; C
     #xE0 #x90 #x90 #x90 #xE0   ; D
     #xF0 #x80 #xF0 #x80 #xF0   ; E
     #xF0 #x80 #xF0 #x80 #x80)) ; F
  "The 16 standard CHIP-8 hex-digit glyphs (0-F), 5 bytes each, in order.")

(defun load-fontset-into-memory! ()
  "Load +CHIP8-FONTSET+ into *MEMORY* at +FONTSET-ADDRESS+ and return it."
  (load-bytes-into-memory +chip8-fontset+ +fontset-address+))
