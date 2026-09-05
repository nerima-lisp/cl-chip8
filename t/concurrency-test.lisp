;;;; Concurrent rendering data and lifecycle tests without a terminal session.
;;;; The cases cover serial fallback, parallel eligibility, and dirty rows.
(in-package #:cl-chip8/test)

(defun %screens-equal-p (left right)
  (loop for y below +screen-height+
        always (loop for x below +screen-width+
                     for left-cell = (screen-cell left x y)
                     for right-cell = (screen-cell right x y)
                     always (and
                             (eql (cell-char left-cell) (cell-char right-cell))
                             (equal (cell-style left-cell) (cell-style right-cell))))))

(defun %expected-half-block (top bottom)
  "The expected half-block glyph for a TOP/BOTTOM pixel pair."
  (cond
    ((and (zerop top) (zerop bottom)) #\Space)
    ((and (zerop top) (= bottom 1)) (code-char #x2584))
    ((and (= top 1) (zerop bottom)) (code-char #x2580))
    (t (code-char #x2588))))

(defun %screen-matches-display-p (screen)
  "True when SCREEN's playfield glyphs match the display framebuffer."
  (loop for terminal-row below (truncate +display-height+ 2)
        for y0 = (* terminal-row 2)
        always (loop for x below +display-width+
                     always (eql
                             (cell-char
                              (screen-cell
                               screen
                               (+ +playfield-origin-x+ x)
                               (+ +playfield-origin-y+ terminal-row)))
                             (%expected-half-block
                              (display-pixel-value x y0)
                              (display-pixel-value x (1+ y0)))))))

(defun %paint-concurrency-pattern! ()
  (display-reset!)
  (dotimes (y +display-height+)
    (dotimes (x +display-width+)
      (when (zerop (mod (+ (* x 3) y) 11))
        (setf (aref *display* y x) 1))))
  ;; Publish the directly written fixture before rendering.
  (display-mark-all-dirty!)
  (set-sound-timer! 7))

(describe
 "render-chip8-concurrently!"
 (before-each (reset-cpu-state!) (display-reset!))
 (it
  "matches the full renderer with a direct full-frame fallback"
  ;; All rows dirty takes the full-frame serial path.
  (%paint-concurrency-pattern!)
  (let ((expected (make-screen +screen-width+ +screen-height+))
        (actual (make-screen +screen-width+ +screen-height+)))
    (with-chip8-render-pipeline
     (pipeline :parallelism 2 :parallel-threshold 4)
     (render-chip8! expected)
     (render-chip8-concurrently! actual pipeline)
     (with-soft-assertions
      (expect (%screen-matches-display-p actual) :to-be t)
      (expect (%screens-equal-p expected actual) :to-be t)
      (expect (chip8-render-pipeline-submitted-rows pipeline) :to-be 0)
      (expect (chip8-render-pipeline-completed-rows pipeline) :to-be 0)
      (expect (chip8-render-pipeline-serial-rows pipeline) :to-be 16)
      (expect (chip8-render-pipeline-queue-depth pipeline) :to-be 0)))))
 (it
 "keeps the measured serial boundary for a medium dirty batch"
 ;; Eight dirty rows are below the minimum concurrent batch size.
 (%paint-concurrency-pattern!)
 (let ((screen (make-screen +screen-width+ +screen-height+))
       (expected (make-screen +screen-width+ +screen-height+)))
   (with-chip8-render-pipeline
    (pipeline :parallelism 2 :parallel-threshold 4)
    (render-chip8-concurrently! screen pipeline)
    (dotimes (terminal-row 8)
      (display-xor-pixel!
       (mod (+ 3 (* terminal-row 5)) +display-width+)
       (* terminal-row 2)))
    (render-chip8! expected)
    (render-chip8-concurrently! screen pipeline)
    (with-soft-assertions
     (expect (%screen-matches-display-p screen) :to-be t)
     ;; Compare the incrementally updated screen with a fresh full render.
     (expect (%screens-equal-p expected screen) :to-be t)
     (expect (chip8-render-pipeline-submitted-rows pipeline) :to-be 0)
     (expect (chip8-render-pipeline-completed-rows pipeline) :to-be 8)
     (expect (chip8-render-pipeline-serial-rows pipeline) :to-be 24)
     (expect (chip8-render-pipeline-queue-depth pipeline) :to-be 0)))))
 (it
  "keeps the serial terminal boundary for a clean display"
  ;; A clean display should not repaint or submit rows.
  (%paint-concurrency-pattern!)
  (let ((screen (make-screen +screen-width+ +screen-height+)))
    (with-chip8-render-pipeline
     (pipeline :parallelism 2 :parallel-threshold 4)
     (render-chip8-concurrently! screen pipeline)
     (let ((submitted-before (chip8-render-pipeline-submitted-rows pipeline))
           (completed-before (chip8-render-pipeline-completed-rows pipeline))
           (serial-before (chip8-render-pipeline-serial-rows pipeline)))
       (render-chip8-concurrently! screen pipeline)
       (with-soft-assertions
        (expect (chip8-render-pipeline-submitted-rows pipeline) :to-be submitted-before)
        (expect (chip8-render-pipeline-completed-rows pipeline) :to-be completed-before)
        (expect (chip8-render-pipeline-serial-rows pipeline) :to-be serial-before)
        (expect (chip8-render-pipeline-queue-depth pipeline) :to-be 0))))))
 (it
  "renders only the terminal row containing a changed pixel"
  ;; A single dirty row stays on the serial path and repaints one row.
  (%paint-concurrency-pattern!)
  (let ((screen (make-screen +screen-width+ +screen-height+))
        (expected (make-screen +screen-width+ +screen-height+)))
    (with-chip8-render-pipeline
     (pipeline :parallelism 2 :parallel-threshold 4)
     (render-chip8-concurrently! screen pipeline)
     (let ((completed-before (chip8-render-pipeline-completed-rows pipeline)))
       (display-xor-pixel! 2 5)
       (render-chip8! expected)
       (render-chip8-concurrently! screen pipeline)
       (with-soft-assertions
        (expect (%screen-matches-display-p screen) :to-be t)
        ;; Compare the incremental update with a fresh full render.
        (expect (%screens-equal-p expected screen) :to-be t)
        (expect (chip8-render-pipeline-submitted-rows pipeline) :to-be 0)
        (expect
         (chip8-render-pipeline-completed-rows pipeline)
         :to-be
         (1+ completed-before))
        (expect (chip8-render-pipeline-serial-rows pipeline) :to-be 17))))))
 (it
  "rejects rendering after the worker pool has been closed"
  (with-chip8-render-pipeline
   (pipeline)
   (with-soft-assertions
    (expect (chip8-render-pipeline-parallel-threshold pipeline) :to-be 13))
   (close-chip8-render-pipeline pipeline)
   (signals
    error
    (render-chip8-concurrently! (make-screen +screen-width+ +screen-height+) pipeline))))
 (it
  "closes the pipeline when its scope unwinds"
  (let ((pipeline nil)
        (screen (make-screen +screen-width+ +screen-height+)))
    (signals
     error
     (with-chip8-render-pipeline
      (candidate :parallelism 1)
      (setf pipeline candidate)
      (error "scope exit")))
    (signals error (render-chip8-concurrently! screen pipeline)))))

(describe
 "render-chip8-concurrently! parallel row batches"
 (before-each (reset-cpu-state!) (display-reset!))
 (it
  "uses persistent CCK workers for a large partial public batch"
  ;; Twelve dirty rows satisfy both concurrency thresholds while avoiding the
  ;; all-rows-dirty serial shortcut.
  (display-reset!)
  (let ((screen (make-screen +screen-width+ +screen-height+))
        (expected (make-screen +screen-width+ +screen-height+)))
    (with-chip8-render-pipeline
     (pipeline :parallelism 2 :parallel-threshold 9)
     (render-chip8-concurrently! screen pipeline)
     (dotimes (terminal-row 12)
       (display-xor-pixel!
        (mod (+ 3 (* terminal-row 5)) +display-width+)
        (* terminal-row 2)))
     (render-chip8! expected)
     (render-chip8-concurrently! screen pipeline)
     (with-soft-assertions
      (expect (%screen-matches-display-p screen) :to-be t)
      (expect (%screens-equal-p expected screen) :to-be t)
      (expect (chip8-render-pipeline-submitted-rows pipeline) :to-be 12)
      (expect (chip8-render-pipeline-completed-rows pipeline) :to-be 12)
      (expect (chip8-render-pipeline-serial-rows pipeline) :to-be 16)
      (expect (chip8-render-pipeline-queue-depth pipeline) :to-be 0))))))

(cl-weave:describe-concurrent
 "concurrent pure row conversion"
 (cl-weave:it-concurrent
  "keeps half block mapping deterministic"
  (let ((actual
         (mapcar
          (lambda (pair)
            (apply (function half-block-character) pair))
          (quote ((0 0) (0 1) (1 0) (1 1))))))
    (with-soft-assertions
     (expect (first actual) :to-be #\Space)
     (expect (second actual) :to-be (code-char #x2584))
     (expect (third actual) :to-be (code-char #x2580))
     (expect (fourth actual) :to-be (code-char #x2588))))))

(cl-weave:it-property
 "maps every pixel pair to its matching half block"
 ((top (cl-weave:gen-integer :min 0 :max 1))
  (bottom (cl-weave:gen-integer :min 0 :max 1)))
 (let ((expected
        (cond
          ((and (zerop top) (zerop bottom)) #\Space)
          ((and (zerop top) (= bottom 1)) (code-char #x2584))
          ((and (= top 1) (zerop bottom)) (code-char #x2580))
          (t (code-char #x2588)))))
   (expect (half-block-character top bottom) :to-be expected)))

;;; Group these cases so the suite's BEFORE-EACH hook resets shared state.

(describe
 "concurrent render dirty-row bookkeeping"
 (before-each (reset-cpu-state!) (display-reset!))
 (it
  "retains a row dirtied after its snapshot"
  (display-reset!)
  (let ((snapshots
          (cl-chip8::with-display-lock (cl-chip8::%snapshot-dirty-display-rows-under-lock))))
    (display-xor-pixel! 0 0)
    (cl-chip8::%clear-rendered-display-rows! snapshots)
    (with-soft-assertions
      (expect (sbit cl-chip8::*display-dirty-rows* 0) :to-be 1)
      (expect (sbit cl-chip8::*display-dirty-rows* 2) :to-be 0))))
 (it
  "handles rows dirtied only on their bottom scanline"
  (display-reset!)
  (let ((screen (make-screen +screen-width+ +screen-height+)))
    (with-chip8-render-pipeline
        (pipeline :parallelism 1 :parallel-threshold 16)
      (render-chip8-concurrently! screen pipeline)
      (display-xor-pixel! 1 1)
      (render-chip8-concurrently! screen pipeline)
      (display-xor-pixel! 1 1)
      (let ((snapshots
              (cl-chip8::with-display-lock (cl-chip8::%snapshot-dirty-display-rows-under-lock))))
        (cl-chip8::%clear-rendered-display-rows! snapshots))
      (with-soft-assertions
        (expect (sbit cl-chip8::*display-dirty-rows* 0) :to-be 0)
        (expect (sbit cl-chip8::*display-dirty-rows* 1) :to-be 0)
        (expect cl-chip8::*display-dirty-terminal-row-count* :to-be 0)))))
 (it
  "allocates a row buffer when no reusable buffer is supplied"
  (display-reset!)
  (let* ((snapshots
           (cl-chip8::with-display-lock (cl-chip8::%snapshot-dirty-display-rows-under-lock)))
         (characters
           (cl-chip8::%render-row-snapshot
            (aref snapshots 0))))
    (with-soft-assertions
     (expect (length characters) :to-be +display-width+)
     (expect (char characters 0) :to-be #\Space)))))

(describe
 "concurrent render failure propagation"
 (before-each (reset-cpu-state!) (display-reset!))
 (it "propagates row worker failures to the caller" (let ((pipeline (make-chip8-render-pipeline :parallelism 1 :parallel-threshold 1))) (unwind-protect (signals error (cl-chip8::%render-snapshots-concurrently (vector (cl-chip8::%make-render-row-snapshot 0 :invalid :invalid 0 0)) pipeline)) (close-chip8-render-pipeline pipeline))))
 (it "signals when the job channel closes before submission" (let ((pipeline (make-chip8-render-pipeline :parallelism 1 :parallel-threshold 1))) (unwind-protect (progn (cl-concurrent-kit:close-channel (cl-chip8::chip8-render-pipeline-jobs-channel pipeline)) (signals error (cl-chip8::%render-snapshots-concurrently (vector (cl-chip8::%make-render-row-snapshot 0 (make-array +display-width+ :element-type (quote bit) :initial-element 0) (make-array +display-width+ :element-type (quote bit) :initial-element 0) 0 0)) pipeline))) (close-chip8-render-pipeline pipeline))))
 (it
  "signals when the job channel is full before submission"
  (let* ((pipeline
           (make-chip8-render-pipeline
            :parallelism 1
            :parallel-threshold 1))
         (replacement (cl-concurrent-kit:make-channel :buffer-size 1)))
    (unwind-protect
        (let ((original
                (cl-chip8::chip8-render-pipeline-jobs-channel pipeline)))
          (unwind-protect
              (progn
                (cl-concurrent-kit:try-send replacement t)
                (setf
                 (cl-chip8::chip8-render-pipeline-jobs-channel pipeline)
                 replacement)
                (signals
                 error
                 (cl-chip8::%render-snapshots-concurrently #() pipeline)))
            (setf
             (cl-chip8::chip8-render-pipeline-jobs-channel pipeline)
             original)))
      (cl-concurrent-kit:close-channel replacement)
      (close-chip8-render-pipeline pipeline))))
 (it
  "signals when worker completion times out"
  (let* ((pipeline
           (make-chip8-render-pipeline
            :parallelism 1
            :parallel-threshold 1
            :shutdown-timeout (cl-date-kit:duration-of-millis 25)))
         (replacement (cl-concurrent-kit:make-channel :buffer-size 1)))
    (unwind-protect
        (let ((original
                (cl-chip8::chip8-render-pipeline-jobs-channel pipeline)))
          (unwind-protect
              (progn
                (setf
                 (cl-chip8::chip8-render-pipeline-jobs-channel pipeline)
                 replacement)
                (signals
                 error
                 (cl-chip8::%render-snapshots-concurrently #() pipeline)))
            (setf
             (cl-chip8::chip8-render-pipeline-jobs-channel pipeline)
             original)))
      (cl-concurrent-kit:close-channel replacement)
      (close-chip8-render-pipeline pipeline)))))

(describe
 "chip8-render-pipeline construction"
 (before-each (reset-cpu-state!) (display-reset!))
 (it
  "exposes the executor high-water mark"
  (with-chip8-render-pipeline
   (pipeline :parallelism 1)
   (with-soft-assertions
    (expect (chip8-render-pipeline-high-water-mark pipeline) :to-be 1))))
 (it
  "uses native duration timeouts for pipeline shutdown"
  (let* ((timeout (cl-date-kit:duration-of-millis 250))
         (pipeline
           (make-chip8-render-pipeline
            :parallelism 1
            :shutdown-timeout timeout)))
    (unwind-protect
        (with-soft-assertions
         (expect
          (typep
           (chip8-render-pipeline-shutdown-timeout pipeline)
           (quote cl-date-kit:duration))
          :to-be
          t))
      (close-chip8-render-pipeline pipeline :timeout timeout)))
  (signals
   type-error
   (make-chip8-render-pipeline :shutdown-timeout 1)))
 (it
  "uses the production render pipeline defaults"
  (let ((pipeline (make-chip8-render-pipeline)))
    (unwind-protect
        (with-soft-assertions
         (expect
          (chip8-render-pipeline-parallelism pipeline)
          :to-be
          +concurrent-render-default-parallelism+)
          (expect (chip8-render-pipeline-parallel-threshold pipeline) :to-be 13))
      (close-chip8-render-pipeline pipeline))))
 (it
  "rejects explicitly supplied NIL pipeline defaults"
  (signals
   type-error
   (make-chip8-render-pipeline :parallelism nil))
  (signals
   type-error
   (make-chip8-render-pipeline :parallel-threshold nil))))

(describe
 "render worker startup failures"
 (before-each (reset-cpu-state!) (display-reset!))
 (it
  "cleans up when worker readiness times out"
  (let* ((executor
           (cl-concurrent-kit:make-executor
            :size 1
            :name "cl-chip8 test startup"
            :queue-capacity 1))
         (jobs-channel (cl-concurrent-kit:make-channel :buffer-size 1))
         (ready-channel (cl-concurrent-kit:make-channel :buffer-size 1))
         (timeout (cl-date-kit:duration-of-millis 25)))
    (unwind-protect
        (signals
         error
         (cl-chip8::%start-render-workers
          executor
          jobs-channel
          ready-channel
          1
          timeout
          (lambda () nil)))
      (cl-concurrent-kit:close-channel jobs-channel)
      (cl-concurrent-kit:shutdown-executor executor :wait t :cancel-pending t :timeout (cl-date-kit:duration-of-millis 250)))))
 (it
  "cleans up when the readiness channel closes"
  (let* ((executor
           (cl-concurrent-kit:make-executor
            :size 1
            :name "cl-chip8 test closed startup"
            :queue-capacity 1))
         (jobs-channel
           (cl-concurrent-kit:make-channel :buffer-size 1))
         (ready-channel
           (cl-concurrent-kit:make-channel :buffer-size 1)))
    (cl-concurrent-kit:close-channel ready-channel)
    (unwind-protect
        (signals
         error
         (cl-chip8::%start-render-workers
          executor
          jobs-channel
          ready-channel
          1
          (cl-date-kit:duration-of-millis 25)
          (lambda () nil)))
      (cl-concurrent-kit:close-channel jobs-channel)
      (cl-concurrent-kit:shutdown-executor
       executor
       :wait t
       :cancel-pending t
       :timeout
       (cl-date-kit:duration-of-millis 250))))))
