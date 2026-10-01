(in-package #:cl-chip8/test)

(defun %render-test-framebuffer ()
  (let ((framebuffer (make-array '(32 64) :element-type 'bit :initial-element 0)))
    (setf (aref framebuffer 0 3) 1 (aref framebuffer 1 3) 1)
    framebuffer))

(defun %render-test-framebuffer-with-rows (rows)
  (let ((framebuffer (make-array '(32 64) :element-type 'bit :initial-element 0)))
    (dolist (row rows framebuffer)
      (setf (aref framebuffer (* row 2) row) 1))))

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

  (it "leaves unchanged rows untouched on a second render"
    (let* ((first (%render-test-framebuffer-with-rows '(0 1)))
           (second (%render-test-framebuffer-with-rows '(0 1)))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
      (setf (aref second 0 1) 1)
      (render-chip8! screen first state)
      (cl-tty-kit:screen-write-string
       screen cl-chip8::+playfield-origin-x+
       (+ cl-chip8::+playfield-origin-y+ 1)
       (make-string cl-chip8::+display-width+ :initial-element #\X)
       :style (cl-tty-kit:make-style :reverse))
      (render-chip8! screen second state)
      (let ((untouched (cl-tty-kit:screen-cell
                        screen cl-chip8::+playfield-origin-x+
                        (+ cl-chip8::+playfield-origin-y+ 1))))
        (expect (cl-tty-kit:cell-char untouched) :to-be #\X)
        (expect (cl-tty-kit:cell-style untouched)
                :to-equal (cl-tty-kit:make-style :reverse)))))

(describe "half-block-character"
  (it "maps all four pixel pairs"
    (expect (cl-chip8::half-block-character 0 0) :to-be #\Space)
    (expect (cl-chip8::half-block-character 1 0) :to-be (code-char #x2580))
    (expect (cl-chip8::half-block-character 0 1) :to-be (code-char #x2584))
    (expect (cl-chip8::half-block-character 1 1) :to-be (code-char #x2588))))
