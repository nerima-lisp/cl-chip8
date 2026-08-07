;;;; src/display.lisp -- the 64x32 monochrome CHIP-8 framebuffer.
;;;;
;;;; Same rationale as memory.lisp: one Prolog fact per pixel would make
;;;; RETRACT/RETRACTALL scan up to 2048 clauses on every sprite draw, so the
;;;; framebuffer is a plain Lisp bit array, wrapped by
;;;; DEFINE-FOREIGN-PREDICATE for Prolog callers.
;;;;
;;;; Boundary with opcode logic (a later stage's concern): this file owns
;;;; single-pixel storage and mutation -- clearing, reading, and XOR-ing one
;;;; bit while reporting whether that XOR erased a set pixel. It does NOT own
;;;; sprite drawing: decoding DXYN's height/registers, walking a sprite's rows
;;;; out of memory, and accumulating the VF collision flag across a whole
;;;; sprite are opcode-decode concerns. DISPLAY-XOR-PIXEL! is the primitive
;;;; DXYN's implementation calls once per bit; it is a display-layer primitive
;;;; because it is about how the framebuffer stores and mutates a single bit,
;;;; not about which opcode is running.
(in-package #:cl-chip8)

(defconstant +display-width+ 64
  "The framebuffer's width in pixels.")

(defconstant +display-height+ 32
  "The framebuffer's height in pixels.")

(defvar *display*
  (make-array (list +display-height+ +display-width+)
              :element-type 'bit
              :initial-element 0)
  "The 64x32 monochrome framebuffer, indexed (ROW COLUMN) i.e. (Y X) --
row-major order matches how a later stage blits this to a terminal screen. A
DEFVAR, not a DEFPARAMETER: reloading this file must not silently wipe the
screen. Call DISPLAY-RESET! to clear it explicitly.")

(defun display-reset! ()
  "Clear every pixel of *DISPLAY* to 0 in place and return it."
  (dotimes (y +display-height+ *display*)
    (dotimes (x +display-width+)
      (setf (aref *display* y x) 0))))

(defun display-pixel-value (x y)
  "Return the bit currently stored at column X, row Y."
  (aref *display* y x))

(defun display-xor-pixel! (x y)
  "XOR the pixel at column X, row Y with 1 and return true when that XOR
erased a previously set pixel (the CHIP-8 sprite-collision condition), false
otherwise."
  (let ((was-set (plusp (aref *display* y x))))
    (setf (aref *display* y x) (logxor (aref *display* y x) 1))
    (and was-set (zerop (aref *display* y x)))))

;;; Prolog-callable primitives.

(define-foreign-predicate (display-clear) (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (display-reset!)
  (funcall emit environment))

(define-foreign-predicate (display-pixel x y value) (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (let ((resolved-x (logic-substitute x environment))
        (resolved-y (logic-substitute y environment)))
    (multiple-value-bind (extended ok)
        (unify value (display-pixel-value resolved-x resolved-y) environment)
      (when ok (funcall emit extended)))))

(define-foreign-predicate (display-xor-pixel x y collided) (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (let* ((resolved-x (logic-substitute x environment))
         (resolved-y (logic-substitute y environment))
         (collision-p (display-xor-pixel! resolved-x resolved-y)))
    (multiple-value-bind (extended ok)
        (unify collided (if collision-p 1 0) environment)
      (when ok (funcall emit extended)))))
