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

(defconstant +screen-width+ (+ +display-width+ 2)
  "Terminal screen width: the 64-pixel-wide playfield plus a 1-cell border on
each side.")

(defconstant +screen-height+ (+ (truncate +display-height+ 2) 2)
  "Terminal screen height: the 32-pixel-tall playfield, two pixel rows per
terminal row, plus a 1-cell border on each side.")

(defparameter +playfield-origin-x+ 1
  "The terminal column the playfield's leftmost pixel column renders at.")

(defparameter +playfield-origin-y+ 1
  "The terminal row the playfield's topmost pixel-pair renders at.")

(defun half-block-character (top-pixel bottom-pixel)
  "Return the half-block character combining TOP-PIXEL and BOTTOM-PIXEL (each
a CHIP-8 display bit, 0 or 1) into one terminal cell: both off is a space,
top-only is U+2580 (upper half block), bottom-only is U+2584 (lower half
block), and both on is U+2588 (full block)."
  (cond
    ((and (zerop top-pixel) (zerop bottom-pixel)) #\Space)
    ((zerop bottom-pixel) (code-char #x2580))
    ((zerop top-pixel) (code-char #x2584))
    (t (code-char #x2588))))

(defun render-display-into-screen! (screen)
  "Blit *DISPLAY* into SCREEN at +PLAYFIELD-ORIGIN-X+/+PLAYFIELD-ORIGIN-Y+
using the half-block scheme this file's header describes. Returns SCREEN."
  (dotimes (terminal-row (truncate +display-height+ 2))
    (dotimes (x +display-width+)
      (let* ((y0 (* terminal-row 2))
             (top (display-pixel-value x y0))
             (bottom (display-pixel-value x (1+ y0))))
        (screen-put-cell screen
                          (+ +playfield-origin-x+ x)
                          (+ +playfield-origin-y+ terminal-row)
                          (half-block-character top bottom)))))
  screen)

(defun sound-timer-active-p ()
  "True when the sound timer is currently nonzero."
  (let ((solutions (query-prolog *rulebase* '(sound-timer ?value))))
    (plusp (solution-binding '?value (first solutions)))))

(defun render-sound-indicator-into-screen! (screen)
  "Style SCREEN's top-left border corner in reverse video while
SOUND-TIMER-ACTIVE-P, else plain -- the visual stand-in for CHIP-8's beep
this application has no audio output for. Returns SCREEN."
  (screen-put-cell screen 0 0 #\Space
                    :style (and (sound-timer-active-p) (make-style :reverse)))
  screen)

(defun render-chip8! (screen)
  "Render one full application frame -- the display and the sound-timer
indicator -- into SCREEN. Returns SCREEN."
  (render-display-into-screen! screen)
  (render-sound-indicator-into-screen! screen)
  screen)
