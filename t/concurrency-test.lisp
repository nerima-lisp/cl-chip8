(in-package #:cl-chip8/test)

(defun %concurrency-test-framebuffer
    (&key (terminal-row-count 16) (width 64)
          (height (* 2 terminal-row-count))
          (element-type 'bit))
  (make-array (list height width)
              :element-type element-type
              :initial-element 0))

(defun %concurrency-test-framebuffer-with-rows
    (rows &key (terminal-row-count 16) (width 64))
  (let ((framebuffer
          (make-array (list (* 2 terminal-row-count) width)
                      :element-type 'bit
                      :initial-element 0)))
    (dolist (terminal-row rows framebuffer)
      (setf (aref framebuffer (* terminal-row 2)
                  (mod terminal-row width))
            1))))

(defun %concurrency-test-framebuffer-with-dirty-rows
    (height width source-rows-per-cell dirty-row-count)
  (let ((framebuffer
          (%concurrency-test-framebuffer
           :height height
           :width width
           :element-type '(unsigned-byte 2))))
    (dotimes (terminal-row dirty-row-count framebuffer)
      (dotimes (source-row source-rows-per-cell)
        (let ((y (+ (* terminal-row source-rows-per-cell) source-row)))
          (dotimes (x width)
            (setf (aref framebuffer y x)
                  (mod (+ x y 1) 4))))))))

(defun %expect-screens-equal
    (expected actual &key (width +screen-width+) (height +screen-height+))
  (dotimes (y height)
    (dotimes (x width)
      (let ((expected-cell (cl-tty-kit:screen-cell expected x y))
            (actual-cell (cl-tty-kit:screen-cell actual x y)))
        (expect (cl-tty-kit:cell-char actual-cell)
                :to-be (cl-tty-kit:cell-char expected-cell))
        (expect (cl-tty-kit:cell-style actual-cell)
                :to-equal (cl-tty-kit:cell-style expected-cell))))))

(describe "render-chip8-concurrently!"
  (it "matches the serial renderer for a framebuffer"
    (let* ((framebuffer (%concurrency-test-framebuffer-with-rows
                         '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14)))
           (blank (make-array '(32 64) :element-type 'bit :initial-element 0))
           (serial (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (parallel (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (serial-state (cl-chip8::make-chip8-render-state)))
      (render-chip8! serial framebuffer serial-state :sound-active-p t)
      (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2 :parallel-threshold 9)
        (render-chip8-concurrently! parallel blank pipeline)
        (render-chip8-concurrently! parallel framebuffer pipeline
                                      :sound-active-p t)
        (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                :to-be 15)
        (expect (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
                :to-be 16))
      (%expect-screens-equal serial parallel))))

  (it "updates only changed rows on a second render"
    (let* ((first (%concurrency-test-framebuffer-with-rows '(0 1)))
           (second (%concurrency-test-framebuffer-with-rows '(0 1)))
           (serial (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (parallel (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (serial-state (cl-chip8::make-chip8-render-state)))
      (setf (aref second 0 1) 1)
      (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2
                                                       :parallel-threshold 9)
        (render-chip8! serial first serial-state)
        (render-chip8-concurrently! parallel first pipeline)
        (cl-tty-kit:screen-write-string
         serial cl-chip8::+playfield-origin-x+
         (+ cl-chip8::+playfield-origin-y+ 1)
         (make-string cl-chip8::+display-width+ :initial-element #\X)
         :style (cl-tty-kit:make-style :reverse))
        (cl-tty-kit:screen-write-string
         parallel cl-chip8::+playfield-origin-x+
         (+ cl-chip8::+playfield-origin-y+ 1)
         (make-string cl-chip8::+display-width+ :initial-element #\X)
         :style (cl-tty-kit:make-style :reverse))
        (render-chip8! serial second serial-state)
        (render-chip8-concurrently! parallel second pipeline)
        (%expect-screens-equal serial parallel)
        (let ((untouched (cl-tty-kit:screen-cell
                          parallel cl-chip8::+playfield-origin-x+
                          (+ cl-chip8::+playfield-origin-y+ 1))))
          (expect (cl-tty-kit:cell-char untouched) :to-be #\X)
          (expect (cl-tty-kit:cell-style untouched)
                  :to-equal (cl-tty-kit:make-style :reverse))))))

(it
    "observes the worker render path through pipeline counters"
  (let ((framebuffer (%concurrency-test-framebuffer-with-rows
                     '(0 1 2 3 4 5 6 7 8)))
        (blank (make-array '(32 64) :element-type 'bit :initial-element 0))
        (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
    (cl-chip8::with-chip8-render-pipeline
        (pipeline :parallelism 2 :parallel-threshold 9)
      (render-chip8-concurrently! screen blank pipeline)
      (let ((submitted-before
              (cl-chip8::chip8-render-pipeline-submitted-rows pipeline))
            (completed-before
              (cl-chip8::chip8-render-pipeline-completed-rows pipeline))
            (serial-before
              (cl-chip8::chip8-render-pipeline-serial-rows pipeline)))
        (render-chip8-concurrently! screen framebuffer pipeline)
        (expect (- (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                   submitted-before)
                :to-be 9)
        (expect (- (cl-chip8::chip8-render-pipeline-completed-rows pipeline)
                   completed-before)
                :to-be 9)
        (expect (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
                :to-be serial-before)))))

(it
    "observes the serial render path through pipeline counters"
  (let ((framebuffer (%concurrency-test-framebuffer-with-rows '(0)))
        (blank (make-array '(32 64) :element-type 'bit :initial-element 0))
        (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
    (cl-chip8::with-chip8-render-pipeline
        (pipeline :parallelism 2 :parallel-threshold 9)
      (render-chip8-concurrently! screen blank pipeline)
      (let ((submitted-before
              (cl-chip8::chip8-render-pipeline-submitted-rows pipeline))
            (completed-before
              (cl-chip8::chip8-render-pipeline-completed-rows pipeline))
            (serial-before
              (cl-chip8::chip8-render-pipeline-serial-rows pipeline)))
        (render-chip8-concurrently! screen framebuffer pipeline)
        (expect (- (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                   submitted-before)
                :to-be 0)
        (expect (- (cl-chip8::chip8-render-pipeline-completed-rows pipeline)
                   completed-before)
                :to-be 1)
        (expect (- (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
                   serial-before)
                :to-be 1)))))

(it
    "scales the default threshold and row buffers with framebuffer geometry"
  (dolist (geometry (quote ((16 64 12 13) (32 128 25 26))))
    (destructuring-bind (terminal-row-count width below-count threshold)
        geometry
      (let* ((blank
               (%concurrency-test-framebuffer
                :terminal-row-count terminal-row-count :width width))
             (below-threshold
               (%concurrency-test-framebuffer-with-rows
                (loop for row below below-count collect row)
                :terminal-row-count terminal-row-count :width width))
             (at-threshold
               (%concurrency-test-framebuffer-with-rows
                (loop for row below threshold collect row)
                :terminal-row-count terminal-row-count :width width))
             (screen
               (cl-tty-kit:make-screen (+ width 2)
                                       (+ terminal-row-count 2))))
        (setf (aref at-threshold 0 (1- width)) 1)
        (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2)
          (render-chip8-concurrently! screen blank pipeline)
          (render-chip8-concurrently! screen below-threshold pipeline)
          (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                  :to-be 0)
          (render-chip8-concurrently! screen blank pipeline)
          (render-chip8-concurrently! screen at-threshold pipeline)
          (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                  :to-be threshold)
          (let ((right-edge
                  (cl-tty-kit:screen-cell
                   screen
                   (+ cl-chip8::+playfield-origin-x+ (1- width))
                   cl-chip8::+playfield-origin-y+)))
            (expect (cl-tty-kit:cell-char right-edge)
                    :to-be (cl-chip8::half-block-character 1 0))))))))

(it
    "scales the minimum batch and keeps an explicit threshold"
  (let* ((terminal-row-count 32)
         (width 64)
         (blank
           (%concurrency-test-framebuffer
            :terminal-row-count terminal-row-count :width width))
         (below-minimum
           (%concurrency-test-framebuffer-with-rows
            (loop for row below 17 collect row)
            :terminal-row-count terminal-row-count :width width))
         (at-minimum
           (%concurrency-test-framebuffer-with-rows
            (loop for row below 18 collect row)
            :terminal-row-count terminal-row-count :width width))
         (screen (cl-tty-kit:make-screen (+ width 2)
                                         (+ terminal-row-count 2))))
    (cl-chip8::with-chip8-render-pipeline
        (pipeline :parallelism 2 :parallel-threshold 1)
      (render-chip8-concurrently! screen blank pipeline)
      (render-chip8-concurrently! screen below-minimum pipeline)
      (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
              :to-be 0)
      (render-chip8-concurrently! screen blank pipeline)
      (render-chip8-concurrently! screen at-minimum pipeline)
      (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
              :to-be 18))))

(it
    "matches serial output in every rendering mode"
  (dolist (geometry
            '((:lores 64 32 2 64 16)
              (:half-block 64 32 2 64 16)
              (:quarter-block 128 64 2 64 32)
              (:braille 128 64 4 64 16)))
    (destructuring-bind
        (mode source-width source-height source-rows-per-cell output-width row-count)
        geometry
      (let* ((blank
               (%concurrency-test-framebuffer
                :height source-height
                :width source-width
                :element-type '(unsigned-byte 2)))
             (framebuffer
               (%concurrency-test-framebuffer-with-dirty-rows
                source-height source-width source-rows-per-cell (1- row-count)))
             (screen-width (+ output-width 2))
             (screen-height (+ row-count 2))
             (serial (cl-tty-kit:make-screen screen-width screen-height))
             (parallel (cl-tty-kit:make-screen screen-width screen-height))
             (serial-state (cl-chip8::make-chip8-render-state)))
        (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2)
          (render-chip8! serial blank serial-state :mode mode)
          (render-chip8-concurrently! parallel blank pipeline :mode mode)
          (render-chip8! serial framebuffer serial-state :mode mode)
          (render-chip8-concurrently! parallel framebuffer pipeline :mode mode)
          (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                  :to-be (1- row-count)))
        (%expect-screens-equal
         serial parallel :width screen-width :height screen-height)))))

(it
    "preserves two-bit framebuffer pixels in worker snapshots"
  (let* ((blank
           (%concurrency-test-framebuffer
            :height 32 :width 64 :element-type '(unsigned-byte 2)))
         (framebuffer
           (%concurrency-test-framebuffer-with-dirty-rows 32 64 2 9))
         (serial (cl-tty-kit:make-screen 66 18))
         (parallel (cl-tty-kit:make-screen 66 18))
         (serial-state (cl-chip8::make-chip8-render-state)))
    (cl-chip8::with-chip8-render-pipeline
        (pipeline :parallelism 2 :parallel-threshold 1)
      (render-chip8! serial blank serial-state :mode :half-block)
      (render-chip8-concurrently! parallel blank pipeline :mode :half-block)
      (render-chip8! serial framebuffer serial-state :mode :half-block)
      (render-chip8-concurrently! parallel framebuffer pipeline :mode :half-block)
      (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
              :to-be 9))
    (%expect-screens-equal serial parallel :width 66 :height 18)))

(it
    "invalidates every row when the display mode changes"
  (let* ((framebuffer
           (%concurrency-test-framebuffer-with-dirty-rows 32 64 2 16))
         (serial (cl-tty-kit:make-screen 66 18))
         (parallel (cl-tty-kit:make-screen 66 18))
         (serial-state (cl-chip8::make-chip8-render-state)))
    (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2)
      (render-chip8! serial framebuffer serial-state :mode :lores)
      (render-chip8-concurrently! parallel framebuffer pipeline :mode :lores)
      (let ((serial-rows-before
              (cl-chip8::chip8-render-pipeline-serial-rows pipeline)))
        (render-chip8! serial framebuffer serial-state :mode :half-block)
        (render-chip8-concurrently! parallel framebuffer pipeline :mode :half-block)
        (expect (- (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
                   serial-rows-before)
                :to-be 16))
      (%expect-screens-equal serial parallel :width 66 :height 18))))

(it
    "invalidates every row when framebuffer geometry changes"
  (let* ((first-framebuffer
           (%concurrency-test-framebuffer-with-dirty-rows 32 64 2 16))
         (second-framebuffer
           (%concurrency-test-framebuffer-with-dirty-rows 34 64 2 17))
         (serial (cl-tty-kit:make-screen 66 19))
         (parallel (cl-tty-kit:make-screen 66 19))
         (serial-state (cl-chip8::make-chip8-render-state)))
    (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2)
      (render-chip8! serial first-framebuffer serial-state :mode :half-block)
      (render-chip8-concurrently!
       parallel first-framebuffer pipeline :mode :half-block)
      (let ((serial-rows-before
              (cl-chip8::chip8-render-pipeline-serial-rows pipeline)))
        (render-chip8! serial second-framebuffer serial-state :mode :half-block)
        (render-chip8-concurrently!
         parallel second-framebuffer pipeline :mode :half-block)
        (expect (- (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
                   serial-rows-before)
                :to-be 17))
      (%expect-screens-equal serial parallel :width 66 :height 19))))
