(in-package #:cl-chip8/test)

(defun %concurrency-test-framebuffer ()
  (let ((framebuffer (make-array '(32 64) :element-type 'bit :initial-element 0)))
    (dotimes (y 32 framebuffer)
      (dotimes (x 64)
        (when (zerop (mod (+ x y) 7))
          (setf (aref framebuffer y x) 1))))))

(defun %concurrency-test-framebuffer-with-rows (rows)
  (let ((framebuffer (make-array '(32 64) :element-type 'bit :initial-element 0)))
    (dolist (terminal-row rows framebuffer)
      (setf (aref framebuffer (* terminal-row 2) terminal-row) 1))))

(defun %expect-screens-equal (expected actual)
  (dotimes (y +screen-height+)
    (dotimes (x +screen-width+)
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
           (serial (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (parallel (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (serial-state (cl-chip8::make-chip8-render-state)))
      (render-chip8! serial framebuffer serial-state :sound-active-p t)
      (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2 :parallel-threshold 9)
        (render-chip8-concurrently! parallel framebuffer pipeline
                                      :sound-active-p t)
        (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                :to-be 15)
        (expect (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
                :to-be 0))
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
