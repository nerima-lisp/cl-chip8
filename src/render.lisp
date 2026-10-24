;;;; Render a framebuffer as half-block terminal cells.
(in-package #:cl-chip8)

(declaim (inline half-block-character)
         (ftype (function (bit bit) character) half-block-character))

(defun half-block-character (top-pixel bottom-pixel)
  (declare (type bit top-pixel bottom-pixel))
  (aref +half-block-character-table+
        (logior bottom-pixel (ash top-pixel 1))))

(defun %render-framebuffer-row-into-screen! (screen framebuffer terminal-row)
  (declare (type (simple-array bit (* *)) framebuffer)
           (type (integer 0 *) terminal-row))
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (y0 (* terminal-row 2))
         (bottom-y (1+ y0))
         (characters (make-string width)))
    (dotimes (x width)
      (setf (char characters x)
            (half-block-character (aref framebuffer y0 x)
                                  (if (< bottom-y height)
                                      (aref framebuffer bottom-y x)
                                      0))))
    (screen-write-string screen +playfield-origin-x+
                         (+ +playfield-origin-y+ terminal-row)
                         characters)))

(defun render-sound-indicator-into-screen! (screen sound-active-p)
  (declare (type boolean sound-active-p))
  (screen-write-string screen 0 0 " "
                       :style (and sound-active-p (make-style :reverse)))
  screen)

(defun render-chip8! (screen framebuffer state &key (sound-active-p nil))
  (declare (type (simple-array bit (* *)) framebuffer)
           (type chip8-render-state state)
           (type boolean sound-active-p))
  (let ((changed (%changed-terminal-rows state framebuffer)))
    (with-screen-batch (screen)
      (dotimes (terminal-row (length changed))
        (when (plusp (sbit changed terminal-row))
          (%render-framebuffer-row-into-screen! screen framebuffer terminal-row)))
      (when (or (null (chip8-render-state-framebuffer state))
                (not (eql sound-active-p
                          (chip8-render-state-sound-active-p state))))
        (render-sound-indicator-into-screen! screen sound-active-p)))
    (setf (chip8-render-state-framebuffer state) (%copy-framebuffer framebuffer)
          (chip8-render-state-sound-active-p state) sound-active-p)
    (incf (chip8-render-state-frame-count state))
    screen))
