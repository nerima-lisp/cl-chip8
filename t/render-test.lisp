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
  (it "blits a set pixel pair as the full block at the playfield offset"
    (display-reset!)
    (setf (aref *display* 0 3) 1)
    (setf (aref *display* 1 3) 1)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-display-into-screen! screen)
      (expect (cell-char (screen-cell screen (+ +playfield-origin-x+ 3) +playfield-origin-y+))
              :to-be (code-char #x2588))))
  (it "blits a clear pixel pair as a space"
    (display-reset!)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-display-into-screen! screen)
      (expect (cell-char (screen-cell screen +playfield-origin-x+ +playfield-origin-y+))
              :to-be #\Space))))

(describe "render-sound-indicator-into-screen!"
  (it "styles the top-left corner in reverse video while the sound timer is nonzero"
    (reset-cpu-state!)
    (set-sound-timer! 5)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-sound-indicator-into-screen! screen)
      (expect (cell-style (screen-cell screen 0 0)) :to-equal '(:reverse))))
  (it "leaves the top-left corner unstyled once the sound timer is 0"
    (reset-cpu-state!)
    (set-sound-timer! 0)
    (let ((screen (make-screen +screen-width+ +screen-height+)))
      (render-sound-indicator-into-screen! screen)
      (expect (cell-style (screen-cell screen 0 0)) :to-be nil))))
