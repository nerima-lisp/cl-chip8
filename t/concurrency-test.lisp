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

(describe "render-chip8-concurrently!"
  (it "matches the serial renderer for a framebuffer"
    (let* ((framebuffer (%concurrency-test-framebuffer))
           (serial (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (parallel (cl-tty-kit:make-screen +screen-width+ +screen-height+))
           (serial-state (cl-chip8::make-chip8-render-state)))
      (render-chip8! serial framebuffer serial-state :sound-active-p t)
      (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 2 :parallel-threshold 1)
        (render-chip8-concurrently! parallel framebuffer pipeline
                                      :sound-active-p t))
      (dotimes (y +screen-height+)
        (dotimes (x +screen-width+)
          (let ((left (cl-tty-kit:screen-cell serial x y))
                (right (cl-tty-kit:screen-cell parallel x y)))
            (expect (cl-tty-kit:cell-char left)
                    :to-be (cl-tty-kit:cell-char right)))))))
  (it "accepts an unchanged framebuffer on a second render"
    (let* ((framebuffer (%concurrency-test-framebuffer))
           (screen (cl-tty-kit:make-screen +screen-width+ +screen-height+)))
      (cl-chip8::with-chip8-render-pipeline (pipeline :parallelism 1)
        (render-chip8-concurrently! screen framebuffer pipeline)
        (render-chip8-concurrently! screen framebuffer pipeline)
        (expect (cl-tty-kit:cell-char
                (cl-tty-kit:screen-cell screen 1 1))
                :to-be (code-char #x2580))))))

(cl-weave:it-isolated
    "observes the worker render path through pipeline counters"
    (:systems ("cl-chip8/test") :timeout 20)
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

(cl-weave:it-isolated
    "observes the serial render path through pipeline counters"
    (:systems ("cl-chip8/test") :timeout 20)
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
