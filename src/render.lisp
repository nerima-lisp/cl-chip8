;;;; Render a framebuffer as half-block terminal cells.
(in-package #:cl-chip8)

(declaim (inline half-block-character)
         (ftype (function (bit bit) character) half-block-character))
(progn
  (defparameter *chip8-render-palette*
    (vector (cl-tty-kit:rgb-to-256 0 0 0)
            (cl-tty-kit:rgb-to-256 0 255 0)
            (cl-tty-kit:rgb-to-256 255 255 0)
            (cl-tty-kit:rgb-to-256 255 255 255)))
  (defstruct (chip8-render-palette-snapshot
              (:constructor %make-chip8-render-palette-snapshot
                  (generation colors)))
    (generation 0 :type (integer 0 *))
    (colors #(nil nil nil nil) :type (simple-array t (4))))
  (defvar *chip8-render-palette-lock* (sb-thread:make-mutex))
  (defvar *chip8-render-palette-snapshot*
    (%make-chip8-render-palette-snapshot
     0 (copy-seq *chip8-render-palette*))))

(defun half-block-character (top-pixel bottom-pixel)
  (declare (type bit top-pixel bottom-pixel))
  (aref +half-block-character-table+
        (logior bottom-pixel (ash top-pixel 1))))

(defun %select-chip8-display-mode (resolution columns rows)
  (declare (type (member :lores :hires) resolution)
           (type (integer 0 *) columns rows))
  (ecase resolution
    (:lores
     (if (and (>= columns 66) (>= rows 18))
         (values :lores 66 18)
         (values :too-small 66 18)))
    (:hires
     (cond
       ((and (>= columns 130) (>= rows 34))
        (values :half-block 130 34))
       ((and (>= columns 66) (>= rows 34))
        (values :quarter-block 66 34))
       ((and (>= columns 66) (>= rows 18))
        (values :braille 66 18))
       (t
        (values :too-small 66 18))))))

(defun %chip8-render-color-to-256 (color)
  (unless (and (stringp color)
               (= (length color) 7)
               (char= (char color 0) #\#)
               (loop for index from 1 below 7
                     always (digit-char-p (char color index) 16)))
    (error "Expected a #RRGGBB color string, got ~S." color))
  (cl-tty-kit:rgb-to-256
   (parse-integer color :start 1 :end 3 :radix 16)
   (parse-integer color :start 3 :end 5 :radix 16)
   (parse-integer color :start 5 :end 7 :radix 16)))

(progn
  (defun %publish-chip8-render-palette! (palette)
    (declare (type (simple-array t (4)) palette))
    (sb-thread:with-mutex (*chip8-render-palette-lock*)
      (let* ((snapshot *chip8-render-palette-snapshot*)
             (colors (copy-seq palette))
             (next-snapshot
               (if (equalp colors
                           (chip8-render-palette-snapshot-colors snapshot))
                   snapshot
                   (%make-chip8-render-palette-snapshot
                    (1+ (chip8-render-palette-snapshot-generation snapshot))
                    colors))))
        (setf *chip8-render-palette-snapshot* next-snapshot
              *chip8-render-palette* palette)))
    palette)
  (defun %capture-chip8-render-palette-snapshot ()
    (sb-thread:with-mutex (*chip8-render-palette-lock*)
      (let ((snapshot *chip8-render-palette-snapshot*))
        (unless (equalp *chip8-render-palette*
                        (chip8-render-palette-snapshot-colors snapshot))
          (setf snapshot
                (%make-chip8-render-palette-snapshot
                 (1+ (chip8-render-palette-snapshot-generation snapshot))
                 (copy-seq *chip8-render-palette*))
                *chip8-render-palette-snapshot* snapshot))
        snapshot)))
  (defun set-chip8-render-palette! (pixels)
    (let ((color-count (and (listp pixels) (list-length pixels))))
      (unless (member color-count '(2 4))
        (error "Expected a proper list of two or four #RRGGBB colors."))
      (let ((palette (make-array 4)))
        (dotimes (index 4)
          (setf (aref palette index)
                (%chip8-render-color-to-256
                 (nth (if (= color-count 2) (min index 1) index)
                      pixels))))
        (%publish-chip8-render-palette! palette)))))

(defun %render-framebuffer-row-data
    (framebuffer pixel-row-start mode
     &optional reusable-characters reusable-styles
       (palette *chip8-render-palette*))
  (declare (type (array * (* *)) framebuffer)
           (type (integer 0 *) pixel-row-start)
           (type (simple-array t (4)) palette))
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (pixels-per-cell-width
           (ecase mode
             (:lores 1)
             (:half-block 1)
             (:quarter-block 2)
             (:braille 2)))
         (cell-count (ceiling width pixels-per-cell-width))
         (characters
           (the (simple-array character (*))
             (if (and (stringp reusable-characters)
                      (= (length reusable-characters) cell-count))
                 reusable-characters
                 (make-string cell-count))))
         (styles
           (unless (eq mode :lores)
             (if (and (typep reusable-styles 'simple-vector)
                      (= (length reusable-styles) cell-count))
                 reusable-styles
                 (make-array cell-count)))))
    (labels ((pixel (y x)
               (if (and (< y height) (< x width))
                   (aref framebuffer y x)
                   0))
             (on-bit (value)
               (if (zerop value) 0 1))
             (style (foreground background)
               (cl-tty-kit:make-style
                (cl-tty-kit:style-fg foreground)
                (cl-tty-kit:style-bg background)))
             (quarter-character (mask)
               (case mask
                 (0 (code-char 32))
                 (1 (code-char #x2598))
                 (2 (code-char #x259D))
                 (3 (code-char #x2580))
                 (4 (code-char #x2596))
                 (5 (code-char #x258C))
                 (6 (code-char #x259E))
                 (7 (code-char #x259B))
                 (8 (code-char #x2597))
                 (9 (code-char #x259A))
                 (10 (code-char #x2590))
                 (11 (code-char #x259C))
                 (12 (code-char #x2584))
                 (13 (code-char #x2599))
                 (14 (code-char #x259F))
                 (15 (code-char #x2588)))))
      (dotimes (cell cell-count)
        (let ((x0 (* cell pixels-per-cell-width))
              (y0 pixel-row-start))
          (ecase mode
            (:lores
             (setf (char characters cell)
                   (half-block-character
                    (on-bit (pixel y0 x0))
                    (on-bit (pixel (1+ y0) x0)))))
            (:half-block
             (let ((top (pixel y0 x0))
                   (bottom (pixel (1+ y0) x0)))
               (setf (char characters cell) (code-char #x2580)
                     (aref styles cell)
                     (style (aref palette top)
                            (aref palette bottom)))))
            (:quarter-block
             (let* ((top-left (pixel y0 x0))
                    (top-right (pixel y0 (1+ x0)))
                    (bottom-left (pixel (1+ y0) x0))
                    (bottom-right (pixel (1+ y0) (1+ x0)))
                    (mask (logior (if (plusp top-left) 1 0)
                                  (if (plusp top-right) 2 0)
                                  (if (plusp bottom-left) 4 0)
                                  (if (plusp bottom-right) 8 0))))
               (setf (char characters cell) (quarter-character mask)
                     (aref styles cell)
                     (style (aref palette 1)
                            (aref palette 0)))))
            (:braille
             (let ((mask 0))
               (loop for offset below 4
                     for y = (+ y0 offset)
                     for left-dot in '(1 2 4 64)
                     for right-dot in '(8 16 32 128)
                     do (when (plusp (pixel y x0))
                          (setf mask (logior mask left-dot)))
                        (when (plusp (pixel y (1+ x0)))
                          (setf mask (logior mask right-dot))))
               (setf (char characters cell)
                     (code-char (+ #x2800 mask))
                     (aref styles cell)
                     (style (aref palette 1)
                            (aref palette 0))))))))
      (values characters styles))))

(defun render-sound-indicator-into-screen! (screen sound-active-p)
  (declare (type boolean sound-active-p))
  (screen-write-string screen 0 0 " "
                       :style (and sound-active-p (make-style :reverse)))
  screen)

(defun render-chip8! (screen framebuffer state
                         &key (sound-active-p nil) (mode :lores))
  (declare (type (array * (* *)) framebuffer)
           (type chip8-render-state state)
           (type boolean sound-active-p))
  (let* ((palette-snapshot (%capture-chip8-render-palette-snapshot))
         (palette-generation
           (chip8-render-palette-snapshot-generation palette-snapshot))
         (palette (chip8-render-palette-snapshot-colors palette-snapshot))
         (changed
           (%changed-terminal-rows
            state framebuffer mode palette-generation))
         (pixels-per-terminal-row
           (ecase mode
             (:lores 2)
             (:half-block 2)
             (:quarter-block 2)
             (:braille 4))))
    (with-screen-batch (screen)
      (dotimes (terminal-row (length changed))
        (when (plusp (sbit changed terminal-row))
          (multiple-value-bind (characters styles)
              (%render-framebuffer-row-data
               framebuffer (* terminal-row pixels-per-terminal-row) mode
               nil nil palette)
            (if styles
                (dotimes (column (length characters))
                  (screen-write-string
                   screen (+ +playfield-origin-x+ column)
                   (+ +playfield-origin-y+ terminal-row)
                   (string (char characters column))
                   :style (aref styles column)))
                (screen-write-string
                 screen +playfield-origin-x+
                 (+ +playfield-origin-y+ terminal-row)
                 characters)))))
      (when (or (null (chip8-render-state-framebuffer state))
                (not (eql sound-active-p
                          (chip8-render-state-sound-active-p state))))
        (render-sound-indicator-into-screen! screen sound-active-p)))
    (setf (chip8-render-state-framebuffer state) (%copy-framebuffer framebuffer)
          (chip8-render-state-sound-active-p state) sound-active-p
          (chip8-render-state-palette-generation state) palette-generation
          (chip8-render-state-display-mode state) mode)
    (incf (chip8-render-state-frame-count state))
    screen))
