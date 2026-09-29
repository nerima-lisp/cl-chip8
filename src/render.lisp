;;;; Render a framebuffer as half-block terminal cells.
(in-package #:cl-chip8)

(declaim (inline half-block-character)
         (ftype (function (bit bit) character) half-block-character))

(defun half-block-character (top-pixel bottom-pixel)
  (declare (type bit top-pixel bottom-pixel))
  (aref +half-block-character-table+
        (logior bottom-pixel (ash top-pixel 1))))

(defun %render-framebuffer-row-into-screen!
    (screen framebuffer terminal-row)
  (declare (type display-framebuffer framebuffer)
           (type display-terminal-row terminal-row))
  (let ((characters (make-string +display-width+))
        (y0 (ash terminal-row 1)))
    (dotimes (x +display-width+)
      (setf (char characters x)
            (half-block-character (aref framebuffer y0 x)
                                  (aref framebuffer (1+ y0) x))))
    (screen-write-string screen +playfield-origin-x+
                         (+ +playfield-origin-y+ terminal-row)
                         characters)))

(defun render-sound-indicator-into-screen! (screen sound-active-p)
  (declare (type boolean sound-active-p))
  (screen-write-string screen 0 0 " "
                       :style (and sound-active-p (make-style :reverse)))
  screen)

(defun render-chip8!
    (screen framebuffer &key (sound-active-p nil))
  (declare (type display-framebuffer framebuffer)
           (type boolean sound-active-p))
  (let* ((cache (%render-cache-for-screen screen))
         (changed (%changed-terminal-rows cache framebuffer)))
    (with-screen-batch (screen)
      (dotimes (terminal-row +display-terminal-row-count+)
        (when (plusp (sbit changed terminal-row))
          (%render-framebuffer-row-into-screen! screen framebuffer terminal-row)))
      (when (or (null (render-cache-framebuffer cache))
                (not (eql sound-active-p (render-cache-sound-active-p cache))))
        (render-sound-indicator-into-screen! screen sound-active-p)))
    (setf (render-cache-framebuffer cache) (%copy-framebuffer framebuffer)
          (render-cache-sound-active-p cache) sound-active-p)
    screen))
