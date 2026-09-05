;;;; t/render-test.lisp -- the half-block glyph logic and screen blitting, in
;;;; isolation from any real terminal.
(in-package #:cl-chip8/test)

(describe "half-block-character"
  (it "returns a space when both pixels are off"
    (expect (half-block-character 0 0) :to-be #\Space))
  (it "returns the upper half block when only the top pixel is on"
    (expect (half-block-character 1 0) :to-be (code-char #x2580)))
  (it "returns the lower half block when only the bottom pixel is on"
    (expect (half-block-character 0 1) :to-be (code-char #x2584)))
  (it "returns the full block when both pixels are on"
    (expect (half-block-character 1 1) :to-be (code-char #x2588))))

(describe "render-display-into-screen!"
  (before-each
    (display-reset!))
  (it "blits a set pixel pair as the full block at the playfield offset"
    (setf (aref *display* 0 3) 1)
    (setf (aref *display* 1 3) 1)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-display-into-screen! screen)
      (expect (cell-char (screen-cell screen (+ +playfield-origin-x+ 3) +playfield-origin-y+))
              :to-be (code-char #x2588))))
  (it "blits a clear pixel pair as a space"
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-display-into-screen! screen)
      (expect (cell-char (screen-cell screen +playfield-origin-x+ +playfield-origin-y+))
              :to-be #\Space))))

(describe "render-sound-indicator-into-screen!"
  (before-each
    (reset-cpu-state!))
  (it "styles the top-left corner in reverse video while the sound timer is nonzero"
    (set-sound-timer! 5)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-sound-indicator-into-screen! screen)
      (expect (cell-style (screen-cell screen 0 0)) :to-equal '(:reverse))))
  (it "leaves the top-left corner unstyled once the sound timer is 0"
    (set-sound-timer! 0)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-sound-indicator-into-screen! screen)
      (expect (cell-style (screen-cell screen 0 0)) :to-be nil))))

(describe "render-chip8!"
  (before-each
    (reset-cpu-state!)
    (display-reset!))
  (it "composes the display blit and the sound indicator into one frame"
    (setf (aref *display* 0 3) 1)
    (setf (aref *display* 1 3) 1)
    (set-sound-timer! 5)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-chip8! screen)
      (with-soft-assertions
        (expect (cell-char (screen-cell screen (+ +playfield-origin-x+ 3) +playfield-origin-y+))
                :to-be (code-char #x2588))
        (expect (cell-style (screen-cell screen 0 0)) :to-equal '(:reverse))))))

;;; Use literal coordinates here so the test remains independent of the
;;; constants that define the playfield placement.
(describe "playfield placement (literal coordinates, not the origin constants)"
  (before-each
    (reset-cpu-state!)
    (display-reset!))
  (it "puts display pixel (0,0) at screen cell (1,1), one row and column inside the border"
    (display-xor-pixel! 0 0)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-chip8! screen)
      (with-soft-assertions
        ;; upper half block: top pixel of the pair set, bottom clear
        (expect (cell-char (screen-cell screen 1 1)) :to-be (code-char #x2580))
        ;; the border column and row the playfield must not encroach on
        (expect (cell-char (screen-cell screen 0 1)) :to-be #\Space)
        (expect (cell-char (screen-cell screen 1 0)) :to-be #\Space))))
  (it "puts the bottom-right display pixel (63,31) at screen cell (64,16)"
    (display-xor-pixel! 63 31)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-chip8! screen)
      ;; lower half block: bottom pixel of the pair set, top clear
      (expect (cell-char (screen-cell screen 64 16)) :to-be (code-char #x2584)))))
