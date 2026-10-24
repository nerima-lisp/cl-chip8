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

(describe "mode-aware rendering"
  (it "selects display modes at the required terminal boundaries"
    (flet ((selection (resolution columns rows)
             (multiple-value-list
              (cl-chip8::%select-chip8-display-mode
               resolution columns rows))))
      (expect (selection :lores 66 18) :to-equal '(:lores 66 18))
      (expect (selection :lores 66 17) :to-equal '(:too-small 66 18))
      (expect (selection :lores 65 18) :to-equal '(:too-small 66 18))
      (expect (selection :hires 130 34) :to-equal '(:half-block 130 34))
      (expect (selection :hires 129 34) :to-equal '(:quarter-block 66 34))
      (expect (selection :hires 66 34) :to-equal '(:quarter-block 66 34))
      (expect (selection :hires 66 18) :to-equal '(:braille 66 18))
      (expect (selection :hires 65 18) :to-equal '(:too-small 66 18))))
  (it "maps two and four palette colors to 256-color entries"
    (let ((original (copy-seq cl-chip8::*chip8-render-palette*)))
      (unwind-protect
           (progn
             (expect
              (equalp
               (set-chip8-render-palette! '("#102030" "#a0b0c0"))
               (vector
                (cl-tty-kit:rgb-to-256 #x10 #x20 #x30)
                (cl-tty-kit:rgb-to-256 #xa0 #xb0 #xc0)
                (cl-tty-kit:rgb-to-256 #xa0 #xb0 #xc0)
                (cl-tty-kit:rgb-to-256 #xa0 #xb0 #xc0)))
              :to-be t)
             (expect
              (equalp
               (set-chip8-render-palette!
                '("#000000" "#00ff00" "#ffff00" "#ffffff"))
               (vector
                (cl-tty-kit:rgb-to-256 0 0 0)
                (cl-tty-kit:rgb-to-256 0 255 0)
                (cl-tty-kit:rgb-to-256 255 255 0)
                (cl-tty-kit:rgb-to-256 255 255 255)))
              :to-be t))
        (cl-chip8::%publish-chip8-render-palette! original))))
  (it "rejects unsupported palette counts and malformed colors"
    (dolist (pixels '(() ("#000000") ("#000000" "#ffffff" "#123456")
                      ("bad" "#ffffff")))
      (expect (handler-case
                  (progn (set-chip8-render-palette! pixels) :accepted)
                (error () :rejected))
              :to-be :rejected)))
  (it "uses four palette entries for half-block cells"
    (let* ((framebuffer
             (make-array '(2 1)
                         :element-type '(unsigned-byte 2)
                         :initial-contents '((2) (3))))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen 3 3)))
      (render-chip8! screen framebuffer state :mode :half-block)
      (expect (cl-tty-kit:cell-char (cl-tty-kit:screen-cell screen 1 1))
              :to-be (code-char #x2580))
      (expect (cl-tty-kit:cell-style (cl-tty-kit:screen-cell screen 1 1))
              :to-equal
              (cl-tty-kit:make-style
               (cl-tty-kit:style-fg
                (aref cl-chip8::*chip8-render-palette* 2))
               (cl-tty-kit:style-bg
                (aref cl-chip8::*chip8-render-palette* 3))))
      (expect (cl-chip8::chip8-render-state-display-mode state)
              :to-be :half-block)))
  (it
    "renders four palette levels for a 64x32 two-plane lores framebuffer"
    (let* ((framebuffer
             (make-array '(32 64)
                         :element-type '(unsigned-byte 2)
                         :initial-element 0))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
      (dotimes (y 32)
        (dotimes (x 64)
          (setf (aref framebuffer y x) (mod (+ x y) 4))))
      (render-chip8! screen framebuffer state :mode :half-block)
      (loop for (column top bottom) in
              (list (list 0 0 1) (list 1 1 2) (list 2 2 3))
            for cell =
              (cl-tty-kit:screen-cell
               screen (+ cl-chip8::+playfield-origin-x+ column)
               cl-chip8::+playfield-origin-y+)
            do (expect (cl-tty-kit:cell-char cell) :to-be (code-char #x2580))
               (expect
                (cl-tty-kit:cell-style cell)
                :to-equal
                (cl-tty-kit:make-style
                 (cl-tty-kit:style-fg
                  (aref cl-chip8::*chip8-render-palette* top))
                 (cl-tty-kit:style-bg
                  (aref cl-chip8::*chip8-render-palette* bottom)))))
      (expect (cl-chip8::chip8-render-state-display-mode state)
              :to-be :half-block)))
  (it "maps every binary quadrant pattern"
    (let ((expected
            (vector (code-char 32)
                    (code-char #x2598) (code-char #x259D)
                    (code-char #x2580) (code-char #x2596)
                    (code-char #x258C) (code-char #x259E)
                    (code-char #x259B) (code-char #x2597)
                    (code-char #x259A) (code-char #x2590)
                    (code-char #x259C) (code-char #x2584)
                    (code-char #x2599) (code-char #x259F)
                    (code-char #x2588))))
      (dotimes (mask 16)
        (let ((framebuffer
                (make-array '(2 2) :element-type 'bit :initial-element 0)))
          (when (logbitp 0 mask) (setf (aref framebuffer 0 0) 1))
          (when (logbitp 1 mask) (setf (aref framebuffer 0 1) 1))
          (when (logbitp 2 mask) (setf (aref framebuffer 1 0) 1))
          (when (logbitp 3 mask) (setf (aref framebuffer 1 1) 1))
          (multiple-value-bind (characters styles)
              (cl-chip8::%render-framebuffer-row-data
               framebuffer 0 :quarter-block)
            (expect (char characters 0) :to-be (aref expected mask))
            (expect (length styles) :to-be 1)
            (expect (aref styles 0)
                    :to-equal
                    (cl-tty-kit:make-style
                     (cl-tty-kit:style-fg
                      (aref cl-chip8::*chip8-render-palette* 1))
                     (cl-tty-kit:style-bg
                      (aref cl-chip8::*chip8-render-palette* 0)))))))))
  (it "maps the eight braille dots and accepts a source-row slice"
    (dolist (dot '((0 0 1) (1 0 2) (2 0 4) (3 0 64)
                   (0 1 8) (1 1 16) (2 1 32) (3 1 128)))
      (destructuring-bind (y x value) dot
        (let ((framebuffer
                (make-array '(4 2) :element-type 'bit :initial-element 0)))
          (setf (aref framebuffer y x) 1)
          (multiple-value-bind (characters styles)
              (cl-chip8::%render-framebuffer-row-data
               framebuffer 0 :braille)
            (expect (char characters 0)
                    :to-be (code-char (+ #x2800 value)))
            (expect (length styles) :to-be 1)))))
    (let ((framebuffer
            (make-array '(4 2) :element-type 'bit :initial-element 1)))
      (multiple-value-bind (characters styles)
          (cl-chip8::%render-framebuffer-row-data framebuffer 0 :braille)
        (expect (char characters 0) :to-be (code-char #x28ff))
        (expect (length styles) :to-be 1))))
  (it "redraws every row when the display mode changes"
    (let* ((framebuffer
             (make-array '(2 1) :element-type 'bit :initial-element 0))
           (state (cl-chip8::make-chip8-render-state))
           (screen (cl-tty-kit:make-screen 3 3)))
      (render-chip8! screen framebuffer state :mode :lores)
      (cl-tty-kit:screen-write-string
       screen cl-chip8::+playfield-origin-x+
       cl-chip8::+playfield-origin-y+ "X"
       :style (cl-tty-kit:make-style :reverse))
      (render-chip8! screen framebuffer state :mode :half-block)
      (expect (cl-tty-kit:cell-char (cl-tty-kit:screen-cell screen 1 1))
              :to-be (code-char #x2580))
      (expect (cl-chip8::chip8-render-state-display-mode state)
              :to-be :half-block)))
  (it "redraws every row when the palette changes"
    (let* ((framebuffer
             (make-array '(32 64) :element-type '(unsigned-byte 2)
                         :initial-element 0))
           (state (cl-chip8::make-chip8-render-state))
           (screen
             (cl-tty-kit:make-screen cl-chip8::+screen-width+
                                      cl-chip8::+screen-height+))
           (original (copy-seq cl-chip8::*chip8-render-palette*)))
      (unwind-protect
           (progn
             (set-chip8-render-palette!
              '("#000000" "#ff0000" "#00ff00" "#0000ff"))
             (dotimes (row 16)
               (dotimes (column 64)
                 (setf (aref framebuffer (* row 2) column) 1)))
             (render-chip8! screen framebuffer state :mode :half-block)
             (dotimes (row 16)
               (cl-tty-kit:screen-write-string
                screen cl-chip8::+playfield-origin-x+
                (+ cl-chip8::+playfield-origin-y+ row) "X"
                :style (cl-tty-kit:make-style :reverse)))
             (set-chip8-render-palette!
              '("#000000" "#ffff00" "#00ffff" "#ffffff"))
             (render-chip8! screen framebuffer state :mode :half-block)
             (dotimes (row 16)
               (let ((cell
                       (cl-tty-kit:screen-cell
                        screen cl-chip8::+playfield-origin-x+
                        (+ cl-chip8::+playfield-origin-y+ row))))
                 (expect (cl-tty-kit:cell-char cell)
                         :to-be (code-char #x2580))
                 (expect (cl-tty-kit:cell-style cell)
                         :to-equal
                         (cl-tty-kit:make-style
                          (cl-tty-kit:style-fg
                           (aref cl-chip8::*chip8-render-palette* 1))
                          (cl-tty-kit:style-bg
                           (aref cl-chip8::*chip8-render-palette* 0)))))))
        (cl-chip8::%publish-chip8-render-palette! original)))))
