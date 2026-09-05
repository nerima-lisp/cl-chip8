;;;; src/display.lisp -- the 64x32 monochrome CHIP-8 framebuffer.
;;;;
;;;; The framebuffer is a Lisp bit array exposed to Prolog through foreign
;;;; predicates. This file provides pixel-level operations; opcode.lisp owns
;;;; sprite traversal and collision accumulation.
(in-package #:cl-chip8)

(declaim (inline %mark-display-row-dirty!
                 %next-display-generation
                 %display-pixel-value
                 %display-xor-pixel-under-lock!)
         (ftype (function (display-row) display-row)
                %mark-display-row-dirty!)
         (ftype (function ((unsigned-byte 64)) (unsigned-byte 64))
                %next-display-generation)
         (ftype (function (display-column display-row) bit)
                %display-pixel-value)
         (ftype (function (display-column display-row) bit)
                display-pixel-value)
         (ftype (function (display-column display-row &optional boolean) boolean)
                %display-xor-pixel-under-lock!)
         (ftype (function (display-column display-row) boolean)
                display-xor-pixel!))

(defun %next-display-generation (generation)
  (declare (type (unsigned-byte 64) generation))
  (ldb (byte 64 0) (1+ generation)))

(defun display-mark-all-dirty! ()
  "Mark every pixel row dirty, advance its generation, and return *DISPLAY*."
  (with-display-lock
   (dotimes (y +display-height+ *display*)
     (declare (type display-row y))
     (setf (sbit *display-dirty-rows* y) 1)
     (setf (aref *display-row-generations* y)
           (%next-display-generation (aref *display-row-generations* y))))
   (setf *display-dirty-terminal-row-count* +display-terminal-row-count+)
   *display*))

(defun %mark-display-row-dirty! (y)
  (declare (type display-row y))
  (let* ((terminal-row (ash y -1))
         (y0 (ash terminal-row 1))
         (was-dirty
          (or (plusp (sbit *display-dirty-rows* y0)) (plusp (sbit *display-dirty-rows* (1+ y0))))))
    (declare (type display-terminal-row terminal-row)
             (type display-row y0))
    (setf (sbit *display-dirty-rows* y) 1)
    (setf (aref *display-row-generations* y)
          (%next-display-generation (aref *display-row-generations* y)))
    (unless was-dirty
      (incf *display-dirty-terminal-row-count*))
    y))

(defun %display-all-terminal-rows-dirty-p ()
  (= *display-dirty-terminal-row-count* +display-terminal-row-count+))

(defun %clear-display-terminal-row-if-unchanged! (terminal-row top-generation bottom-generation)
  (declare (type display-terminal-row terminal-row)
           (type (unsigned-byte 64) top-generation bottom-generation))
  (let ((y0 (ash terminal-row 1)))
    (when (and
           (= (aref *display-row-generations* y0) top-generation)
           (= (aref *display-row-generations* (1+ y0)) bottom-generation))
      (let ((was-dirty
             (or (plusp (sbit *display-dirty-rows* y0)) (plusp (sbit *display-dirty-rows* (1+ y0))))))
        (setf (sbit *display-dirty-rows* y0) 0
              (sbit *display-dirty-rows* (1+ y0)) 0)
        (when was-dirty
          (decf *display-dirty-terminal-row-count*)))
      t)))

(defun display-reset! ()
  "Clear every pixel of *DISPLAY* in place and return it."
  (with-display-lock
   (dotimes (i (* +display-width+ +display-height+))
     (declare (type fixnum i))
     (setf (row-major-aref *display* i) 0))
   (fill *display-dirty-rows* 1)
   (dotimes (y +display-height+)
     (declare (type display-row y))
     (setf (aref *display-row-generations* y)
           (%next-display-generation (aref *display-row-generations* y))))
   (setf *display-dirty-terminal-row-count* +display-terminal-row-count+)
   *display*))

(defun %display-pixel-value (x y)
  (declare (type display-column x) (type display-row y))
  (aref *display* y x))

(defun display-pixel-value (x y)
  "Return the bit currently stored at column X, row Y."
  (check-type x display-column)
  (check-type y display-row)
  (with-display-lock (%display-pixel-value x y)))

(defun %display-xor-pixel-under-lock! (x y &optional (mark-dirty-p t))
  (declare (type display-column x)
           (type display-row y)
           (type boolean mark-dirty-p))
  (let* ((old-value (aref *display* y x))
         (new-value (logxor old-value 1)))
    (setf (aref *display* y x) new-value)
    (when mark-dirty-p
      (%mark-display-row-dirty! y))
    (and (plusp old-value) (zerop new-value))))

(defun display-xor-pixel! (x y)
  "XOR the pixel at column X, row Y with 1 and return true when that XOR
erased a previously set pixel (the CHIP-8 sprite-collision condition), false
otherwise."
  (check-type x display-column)
  (check-type y display-row)
  (with-display-lock
   (%display-xor-pixel-under-lock! x y)))

;;; Prolog-callable primitives.
(define-foreign-predicate
 (display-clear)
 (rulebase environment depth emit)
 (display-reset!)
 (funcall emit environment))

(define-foreign-predicate
 (display-pixel x y value)
 (rulebase environment depth emit)
 (let ((resolved-x (logic-substitute x environment))
       (resolved-y (logic-substitute y environment)))
   (check-type resolved-x display-column)
   (check-type resolved-y display-row)
   (multiple-value-bind (extended ok) (unify
                                       value
                                       (display-pixel-value resolved-x resolved-y)
                                       environment)
     (when ok
       (funcall emit extended)))))

(define-foreign-predicate
 (display-xor-pixel x y collided)
 (rulebase environment depth emit)
 (let* ((resolved-x (logic-substitute x environment))
        (resolved-y (logic-substitute y environment)))
   (check-type resolved-x display-column)
   (check-type resolved-y display-row)
   (let ((collision-p (display-xor-pixel! resolved-x resolved-y)))
   (multiple-value-bind (extended ok) (unify
                                       collided
                                       (if collision-p 1
                                         0)
                                       environment)
     (when ok
       (funcall emit extended))))))
