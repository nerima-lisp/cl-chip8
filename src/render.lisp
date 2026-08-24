;;;; src/render.lisp -- blitting *DISPLAY* into a cl-tty-kit SCREEN.
;;;;
;;;; CHIP-8's 64x32 monochrome framebuffer is rendered two pixel-rows per
;;;; terminal cell using half-block glyphs (U+2580 UPPER HALF BLOCK, U+2584
;;;; LOWER HALF BLOCK, U+2588 FULL BLOCK, and plain space): the top pixel of
;;;; each pair picks the glyph's upper half, the bottom pixel its lower half,
;;;; so a 64x32 field renders as 64 columns by 16 terminal rows. That
;;;; playfield sits inset by a 1-cell border on every side (see
;;;; +PLAYFIELD-ORIGIN-X+/+PLAYFIELD-ORIGIN-Y+ below), so the top-left border
;;;; corner has a cell of its own to carry the sound-timer indicator without
;;;; overlapping the playfield itself -- CHIP-8 has no audio output in this
;;;; application (see the brief's "no audio" quirk decision), so a reverse-
;;;; video corner cell stands in for the beep for as long as the sound timer
;;;; is nonzero.
(in-package #:cl-chip8)

(declaim (inline half-block-character)
         (ftype (function (bit bit) character)
                half-block-character))

(defun half-block-character (top-pixel bottom-pixel)
  "Return the half-block character for two display bits."
  (declare (type bit top-pixel bottom-pixel))
  (aref +half-block-character-table+
        (logior bottom-pixel (ash top-pixel 1))))
(defvar *render-row-buffer* nil)

(check-type *render-row-buffer* (or null (simple-array t (16))))

(declaim (type (or null (simple-array t (16))) *render-row-buffer*))

(declaim (inline %ensure-render-row-buffer)
         (ftype (function () (simple-array t (16)))
                %ensure-render-row-buffer))

(defun %render-display-row-into-screen!
    (screen terminal-row &optional reusable-characters)
  "Blit one display row into SCREEN without acquiring locks or batching SCREEN."
  (declare (type display-terminal-row terminal-row)
           (type (or null (vector t 16)) reusable-characters))
  (let ((characters
          (or (and reusable-characters
                   (aref reusable-characters terminal-row))
                   (make-string +display-width+)))
        (y0 (ash terminal-row 1)))
    (declare (type string characters)
             (type display-row y0))
    (dotimes (x +display-width+)
      (declare (type display-column x))
      (setf (char characters x)
            (half-block-character
             (%display-pixel-value x y0)
             (%display-pixel-value x (1+ y0)))))
    (screen-write-string
     screen
     +playfield-origin-x+
     (+ +playfield-origin-y+ terminal-row)
     characters)))

(defun %render-display-into-screen!
    (screen &optional reusable-characters)
  "Blit *DISPLAY* into SCREEN without acquiring the display lock or batching SCREEN."
  (declare (type (or null (vector t 16)) reusable-characters))
  (dotimes (terminal-row +display-terminal-row-count+)
    (declare (type display-terminal-row terminal-row))
    (%render-display-row-into-screen!
     screen
     terminal-row
     reusable-characters))
  screen)
(defun %ensure-render-row-buffer ()
  (or *render-row-buffer*
      (setf *render-row-buffer*
            (let ((buffer (make-array +display-terminal-row-count+
                                      :element-type t
                                      :initial-element nil)))
              (declare (type (simple-array t (16)) buffer))
              (dotimes (terminal-row (length buffer) buffer)
                (declare (type display-terminal-row terminal-row))
                (setf (aref buffer terminal-row)
                      (make-string +display-width+)))))))

(defun render-display-into-screen! (screen)
  "Blit *DISPLAY* into SCREEN under the display lock. Returns SCREEN."
  (with-display-lock
    (with-screen-batch (screen)
      (%render-display-into-screen!
       screen
       (%ensure-render-row-buffer))))
  screen)

(defun sound-timer-active-p ()
  "True when the sound timer is currently nonzero."
  (plusp (solution-binding
          '?value
          (query-prolog-first *rulebase* '(sound-timer ?value)))))

(defun render-sound-indicator-into-screen! (screen)
  "Style SCREEN's top-left border corner in reverse video while
SOUND-TIMER-ACTIVE-P, else plain -- the visual stand-in for CHIP-8's beep
this application has no audio output for. Returns SCREEN."
  (screen-write-string
   screen
   0
   0
   " "
   :style (and (sound-timer-active-p) (make-style :reverse)))
  screen)

(defun render-chip8! (screen)
  "Render one full application frame -- the display and the sound-timer indicator -- into SCREEN. Returns SCREEN."
  (with-display-lock
    (with-screen-batch (screen)
      (%render-display-into-screen!
       screen
       (%ensure-render-row-buffer))
      (render-sound-indicator-into-screen! screen)))
  screen)
