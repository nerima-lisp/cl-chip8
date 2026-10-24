;;;; src/render-types.lisp -- terminal rendering constants and lookup data.
(in-package #:cl-chip8)

(deftype column () '(integer 0 63))
(deftype row () '(integer 0 31))
(deftype terminal-row () '(integer 0 15))
(deftype row-bits () '(simple-array bit (64)))

(defconstant +screen-width+ (+ +display-width+ 2)
  "Terminal screen width: the 64-pixel-wide playfield plus a 1-cell border on
each side.")

(defconstant +screen-height+ (+ +display-terminal-row-count+ 2)
  "Terminal screen height: the 32-pixel-tall playfield, two pixel rows per
terminal row, plus a 1-cell border on each side.")

(defparameter +playfield-origin-x+ 1
  "The terminal column the playfield's leftmost pixel column renders at.")

(defparameter +playfield-origin-y+ 1
  "The terminal row the playfield's topmost pixel-pair renders at.")

(defparameter +half-block-character-table+
  (make-array 4
              :element-type 'character
              :initial-contents
              (list #\Space
                    (code-char #x2584)
                    (code-char #x2580)
                    (code-char #x2588)))
  "Character lookup for the four two-pixel terminal cells.")

(declaim (type (integer 0 *) +playfield-origin-x+)
         (type (integer 0 *) +playfield-origin-y+)
         (type (simple-array character (4)) +half-block-character-table+))

(defstruct (chip8-render-state (:constructor make-chip8-render-state))
  (framebuffer nil :type (or null (simple-array bit (* *))))
  (sound-active-p nil :type boolean)
  (frame-count 0 :type (unsigned-byte 64)))

(defun %copy-framebuffer (framebuffer)
  (declare (type (simple-array bit (* *)) framebuffer))
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (copy (make-array (list height width) :element-type 'bit)))
    (dotimes (y height copy)
      (dotimes (x width)
        (setf (aref copy y x) (aref framebuffer y x))))))

(defun %changed-terminal-rows (state framebuffer)
  (declare (type chip8-render-state state)
           (type (simple-array bit (* *)) framebuffer))
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (terminal-row-count (ceiling height 2))
         (previous (chip8-render-state-framebuffer state))
         (same-dimensions-p
           (and previous
                (equal (array-dimensions previous)
                       (array-dimensions framebuffer))))
         (rows (make-array terminal-row-count
                           :element-type 'bit :initial-element 0)))
    (dotimes (terminal-row terminal-row-count rows)
      (let ((y0 (* terminal-row 2)))
        (when (or (not same-dimensions-p)
                  (loop for y from y0 below (min height (+ y0 2))
                        thereis (loop for x below width
                                      thereis
                                      (not (eql (aref previous y x)
                                                (aref framebuffer y x))))))
          (setf (sbit rows terminal-row) 1))))))
