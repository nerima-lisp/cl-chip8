(in-package #:cl-chip8/test)

(defun %render-test-framebuffer ()
  (let ((framebuffer (make-array '(32 64) :element-type 'bit :initial-element 0)))
    (setf (aref framebuffer 0 3) 1 (aref framebuffer 1 3) 1)
    framebuffer))

(describe "render-chip8!"
  (it "renders framebuffer pixels as terminal half-blocks"
    (let* ((framebuffer (%render-test-framebuffer))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
      (render-chip8! screen framebuffer state :sound-active-p t)
      (expect (cl-tty-kit:cell-char (cl-tty-kit:screen-cell screen 4 1))
              :to-be (code-char #x2588))
      (expect (cl-tty-kit:cell-style (cl-tty-kit:screen-cell screen 0 0))
              :to-equal '(:reverse))))
  (it "does not alias the caller framebuffer through render state"
    (let* ((framebuffer (%render-test-framebuffer))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
      (render-chip8! screen framebuffer state)
      (setf (aref framebuffer 0 3) 0)
      (expect (aref (cl-chip8::chip8-render-state-framebuffer state) 0 3)
              :to-be 1))))

(describe "half-block-character"
  (it "maps all four pixel pairs"
    (expect (cl-chip8::half-block-character 0 0) :to-be #\Space)
    (expect (cl-chip8::half-block-character 1 0) :to-be (code-char #x2580))
    (expect (cl-chip8::half-block-character 0 1) :to-be (code-char #x2584))
    (expect (cl-chip8::half-block-character 1 1) :to-be (code-char #x2588))))
