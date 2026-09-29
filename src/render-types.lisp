;;;; src/render-types.lisp -- terminal rendering constants and lookup data.
(in-package #:cl-chip8)

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
  (framebuffer nil :type (or null display-framebuffer))
  (sound-active-p nil :type boolean))

(defun %copy-framebuffer (framebuffer)
  (declare (type display-framebuffer framebuffer))
  (adjust-array (copy-seq framebuffer) '(32 64)))

(defun %changed-terminal-rows (state framebuffer)
  (declare (type chip8-render-state state) (type display-framebuffer framebuffer))
  (let ((previous (chip8-render-state-framebuffer state))
        (rows (make-array +display-terminal-row-count+
                          :element-type 'bit :initial-element 0)))
    (dotimes (terminal-row +display-terminal-row-count+ rows)
      (let ((y0 (ash terminal-row 1)))
        (when (or (null previous)
                  (loop for y from y0 to (1+ y0)
                        thereis (loop for x below +display-width+
                                      thereis (not (eql (aref previous y x)
                                                      (aref framebuffer y x))))))
          (setf (sbit rows terminal-row) 1))))))
