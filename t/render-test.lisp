(in-package #:cl-chip8/test)

(defun %render-test-framebuffer
    (&optional (width +display-width+) (height +display-height+))
  (let ((framebuffer (make-array (list height width)
                                 :element-type 'bit :initial-element 0)))
    (setf (aref framebuffer 0 0) 1
          (aref framebuffer 1 1) 1
          (aref framebuffer 0 3) 1
          (aref framebuffer 1 3) 1)
    framebuffer))

(defun %render-test-framebuffer-with-rows
    (rows &optional (width +display-width+) (height +display-height+))
  (let ((framebuffer (make-array (list height width)
                                 :element-type 'bit :initial-element 0)))
    (dolist (row rows framebuffer)
      (setf (aref framebuffer (* row 2) row) 1))))

(describe "render-chip8!"
  (it "renders framebuffer pixels as terminal half-blocks"
    (let* ((framebuffer (%render-test-framebuffer))
           (height (array-dimension framebuffer 0))
           (width (array-dimension framebuffer 1))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (expected-screen
             (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
      (loop for y0 from 0 below height by 2
            for terminal-row from 0
            do (let ((characters (make-string width))
                     (bottom-y (1+ y0)))
                 (dotimes (x width)
                   (let ((top (aref framebuffer y0 x))
                         (bottom (if (< bottom-y height)
                                     (aref framebuffer bottom-y x)
                                     0)))
                     (setf (char characters x)
                           (cond
                             ((and (= top 1) (= bottom 1)) (code-char #x2588))
                             ((= top 1) (code-char #x2580))
                             ((= bottom 1) (code-char #x2584))
                             (t #\Space)))))
                 (cl-tty-kit:screen-write-string
                  expected-screen cl-chip8::+playfield-origin-x+
                  (+ cl-chip8::+playfield-origin-y+ terminal-row)
                  characters)))
      (cl-tty-kit:screen-write-string
       expected-screen 0 0 " "
       :style (cl-tty-kit:make-style :reverse))
      (render-chip8! screen framebuffer state :sound-active-p t)
      (expect (cl-tty-kit:cell-char (cl-tty-kit:screen-cell screen 4 1))
              :to-be (code-char #x2588))
      (expect (cl-tty-kit:cell-style (cl-tty-kit:screen-cell screen 0 0))
              :to-equal '(:reverse))
      (expect (equalp (sb-ext:string-to-octets
                       (cl-tty-kit:render-screen screen)
                       :external-format :utf-8)
                     (sb-ext:string-to-octets
                       (cl-tty-kit:render-screen expected-screen)
                       :external-format :utf-8))
              :to-be t)))
  (it "does not alias the caller framebuffer through render state"
    (let* ((framebuffer (%render-test-framebuffer))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
      (render-chip8! screen framebuffer state)
      (setf (aref framebuffer 0 3) 0)
      (expect (aref (cl-chip8::chip8-render-state-framebuffer state) 0 3)
              :to-be 1)))
  (it "preserves unchanged rows and derives render dimensions from the framebuffer"
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
                :to-equal (cl-tty-kit:make-style :reverse))))
    (let* ((width (* 2 +display-width+))
           (height (1+ (* 2 +display-height+)))
           (framebuffer (make-array (list height width)
                                    :element-type 'bit :initial-element 0))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen (+ width 2)
                                           (+ (ceiling height 2) 2))))
      (setf (aref framebuffer (1- height) (1- width)) 1)
      (render-chip8! screen framebuffer state)
      (expect (array-dimensions
               (cl-chip8::chip8-render-state-framebuffer state))
              :to-equal (list height width))
      (expect (cl-tty-kit:cell-char
               (cl-tty-kit:screen-cell
                screen (+ (1- width) cl-chip8::+playfield-origin-x+)
                (+ (1- (ceiling height 2))
                   cl-chip8::+playfield-origin-y+)))
              :to-be (code-char #x2580)))))

(describe "half-block-character"
  (it "maps all four pixel pairs"
    (expect (cl-chip8::half-block-character 0 0) :to-be #\Space)
    (expect (cl-chip8::half-block-character 1 0) :to-be (code-char #x2580))
    (expect (cl-chip8::half-block-character 0 1) :to-be (code-char #x2584))
    (expect (cl-chip8::half-block-character 1 1) :to-be (code-char #x2588))))
