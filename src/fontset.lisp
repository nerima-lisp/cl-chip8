;;;; src/fontset.lisp -- the built-in CHIP-8 hex-digit fontset.
;;;;
;;;; These 80 bytes encode 16 glyphs of 5 bytes each. Each row uses the
;;;; glyph's four most-significant bits, matching the standard CHIP-8 fontset.
(in-package #:cl-chip8)

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

(defconstant +big-fontset-address+ #xa0)

(defparameter +chip8-big-fontset+
  (make-array
   160 :element-type 'chip8-octet
   :initial-contents
   '(#xff #xff #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xff #xff
     #x18 #x78 #x78 #x18 #x18 #x18 #x18 #x18 #xff #xff
     #xff #xff #x03 #x03 #xff #xff #xc0 #xc0 #xff #xff
     #xff #xff #x03 #x03 #xff #xff #x03 #x03 #xff #xff
     #xc3 #xc3 #xc3 #xc3 #xff #xff #x03 #x03 #x03 #x03
     #xff #xff #xc0 #xc0 #xff #xff #x03 #x03 #xff #xff
     #xff #xff #xc0 #xc0 #xff #xff #xc3 #xc3 #xff #xff
     #xff #xff #x03 #x03 #x06 #x0c #x18 #x18 #x18 #x18
     #xff #xff #xc3 #xc3 #xff #xff #xc3 #xc3 #xff #xff
     #xff #xff #xc3 #xc3 #xff #xff #x03 #x03 #xff #xff
     #x7e #xff #xc3 #xc3 #xc3 #xff #xff #xc3 #xc3 #xc3
     #xfc #xfc #xc3 #xc3 #xfc #xfc #xc3 #xc3 #xfc #xfc
     #x3c #xff #xc3 #xc0 #xc0 #xc0 #xc0 #xc3 #xff #x3c
     #xfc #xfe #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xfe #xfc
     #xff #xff #xc0 #xc0 #xff #xff #xc0 #xc0 #xff #xff
     #xff #xff #xc0 #xc0 #xff #xff #xc0 #xc0 #xc0 #xc0)))

(defun load-fontset-into-memory! (machine)
  (load-bytes-into-memory machine +chip8-fontset+ +fontset-address+)
  (load-bytes-into-memory machine +chip8-big-fontset+
                          +big-fontset-address+))
