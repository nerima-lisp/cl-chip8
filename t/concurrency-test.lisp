;;;; t/concurrency-test.lisp -- concurrent rendering's data and lifecycle
;;;; contracts, without starting a terminal session.
;;;;
;;;; On render-path coverage: RENDER-CHIP8-CONCURRENTLY! has three paths, and
;;;; which one a test takes is decided entirely by the dirty-row count and the
;;;; pipeline's threshold, never by the test's name. The gates are
;;;;
;;;;   1. every terminal row dirty      -> full-frame serial fallback, taken at
;;;;      src/concurrent-render-rows.lisp:217-219
;;;;   2. otherwise %CCK-RENDER-ELIGIBLE-P at src/concurrent-render-rows.lisp:166-173,
;;;;      which needs the dirty count to clear BOTH the configured
;;;;      :PARALLEL-THRESHOLD and +CONCURRENT-RENDER-MINIMUM-SNAPSHOTS+, a
;;;;      constant 9 (src/concurrent-render-types.lisp:58)
;;;;   3. anything below that            -> serial dirty-row fallback
;;;;
;;;; The second gate is the surprising one: a batch of 8 dirty rows with
;;;; :PARALLEL-THRESHOLD 4 still renders serially, because 8 < 9. Each test
;;;; below states the path it exercises, and its pipeline counter assertions
;;;; are what prove that claim -- SUBMITTED-ROWS stays 0 on every serial path
;;;; and is nonzero only on the concurrent one.
;;;;
;;;; On screen comparison: comparing a RENDER-CHIP8! screen against a
;;;; RENDER-CHIP8-CONCURRENTLY! screen is only a real check when the two sides
;;;; did different work. It is a genuine differential when one side is a fresh
;;;; full render and the other is an incrementally updated screen, since a
;;;; dirty row the incremental path failed to repaint shows up as stale
;;;; content. It proves nothing when both sides are fresh full renders through
;;;; the same primitive. %SCREEN-MATCHES-DISPLAY-P below is the independent
;;;; oracle used where that distinction matters.
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
  "The half-block glyph a TOP/BOTTOM pixel pair must render as, spelled out as
an explicit case table rather than by calling HALF-BLOCK-CHARACTER. Restating
the mapping is the point: an oracle that called the renderer's own lookup would
agree with it by construction, including when both are wrong."
  (cond
    ((and (zerop top) (zerop bottom)) #\Space)
    ((and (zerop top) (= bottom 1)) (code-char #x2584))
    ((and (= top 1) (zerop bottom)) (code-char #x2580))
    (t (code-char #x2588))))

(defun %screen-matches-display-p (screen)
  "True when every playfield cell of SCREEN carries the glyph *DISPLAY*'s pixel
pair calls for, judged against %EXPECTED-HALF-BLOCK.

This is the check that survives both renderers being wrong the same way.
Comparing two rendered screens cannot fail when both sides reach the same
row-blitting primitive, because a defect inside that primitive corrupts both
equally; this compares one rendered screen against the framebuffer it claims to
depict. Covers glyphs in the playfield only -- not the border, and not cell
styles, which the sound indicator owns."
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
  ;; The pattern uses direct bit writes to build a fixture, so publish the
  ;; complete snapshot explicitly before the first render.
  (display-mark-all-dirty!)
  (set-sound-timer! 7))

(describe
 "render-chip8-concurrently!"
 (before-each (reset-cpu-state!) (display-reset!))
 (it
  "matches the full renderer with a direct full-frame fallback"
  ;; PATH: full-frame serial fallback. %PAINT-CONCURRENCY-PATTERN! ends in
  ;; DISPLAY-MARK-ALL-DIRTY!, so all 16 terminal rows are dirty and
  ;; src/concurrent-render-rows.lisp:217-219 short-circuits before the
  ;; eligibility test is ever reached. SERIAL-ROWS 16 with SUBMITTED-ROWS 0
  ;; below is the proof of that; no worker runs in this test.
  (%paint-concurrency-pattern!)
  (let ((expected (make-screen +screen-width+ +screen-height+))
        (actual (make-screen +screen-width+ +screen-height+)))
    (with-chip8-render-pipeline
     (pipeline :parallelism 2 :parallel-threshold 4)
     (render-chip8! expected)
     (render-chip8-concurrently! actual pipeline)
     (with-soft-assertions
      ;; The independent oracle. Both screens here are fresh full renders that
      ;; reach the same %RENDER-DISPLAY-INTO-SCREEN!, so %SCREENS-EQUAL-P alone
      ;; cannot fail on glyph content however wrong that primitive is -- it
      ;; only catches the fallback composing the frame differently (dropping
      ;; the sound indicator, or corrupting output via the reusable row
      ;; buffer it passes where RENDER-CHIP8! passes NIL). This assertion is
      ;; what actually checks the pixels reached the screen.
      (expect (%screen-matches-display-p actual) :to-be t)
      (expect (%screens-equal-p expected actual) :to-be t)
      (expect (chip8-render-pipeline-submitted-rows pipeline) :to-be 0)
      (expect (chip8-render-pipeline-completed-rows pipeline) :to-be 0)
      (expect (chip8-render-pipeline-serial-rows pipeline) :to-be 16)
      (expect (chip8-render-pipeline-queue-depth pipeline) :to-be 0)))))
 (it
 "keeps the measured serial boundary for a medium dirty batch"
 ;; PATH: serial dirty-row fallback, and this test exists to pin exactly why.
 ;; 8 dirty rows clears the configured :PARALLEL-THRESHOLD 4, so the threshold
 ;; alone would admit it -- but %CCK-RENDER-ELIGIBLE-P also requires
 ;; +CONCURRENT-RENDER-MINIMUM-SNAPSHOTS+, which is 9, and 8 < 9. Lower that
 ;; constant to 8 and SUBMITTED-ROWS below goes nonzero and the test fails,
 ;; which is what makes the assertion load-bearing rather than decorative.
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
     ;; Unlike the full-frame test above, this comparison is a real
     ;; differential: EXPECTED is a fresh full render while SCREEN was painted
     ;; once and then only had its 8 dirty rows repainted. A row the dirty
     ;; tracking failed to mark would keep its stale content in SCREEN and
     ;; differ from EXPECTED here.
     (expect (%screens-equal-p expected screen) :to-be t)
     (expect (chip8-render-pipeline-submitted-rows pipeline) :to-be 0)
     (expect (chip8-render-pipeline-completed-rows pipeline) :to-be 8)
     (expect (chip8-render-pipeline-serial-rows pipeline) :to-be 24)
     (expect (chip8-render-pipeline-queue-depth pipeline) :to-be 0)))))
 (it
  "keeps the serial terminal boundary for a clean display"
  ;; PATH: serial dirty-row fallback over an empty dirty set. The second render
  ;; must move no counter at all, which is why every expectation is against the
  ;; value captured before it rather than against a literal.
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
  ;; PATH: serial dirty-row fallback with a single dirty row (1 < 9, so the
  ;; concurrent path is unreachable here by construction). SERIAL-ROWS moving
  ;; 16 -> 17 is the assertion that only one row was repainted.
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
        ;; A real differential for the same reason as the medium-batch test:
        ;; SCREEN is incrementally updated, EXPECTED is a fresh full render.
        ;; Repainting the wrong single row leaves the changed pixel stale in
        ;; SCREEN and fails here.
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
  ;; PATH: the concurrent one -- the only test in this file that reaches it.
  ;; 12 dirty rows clears both gates: the explicit :PARALLEL-THRESHOLD 9 and
  ;; +CONCURRENT-RENDER-MINIMUM-SNAPSHOTS+ 9. It must also stay under 16, or
  ;; the all-rows-dirty short-circuit would take the full-frame serial path
  ;; before eligibility is consulted. SUBMITTED-ROWS 12 is the proof that
  ;; workers ran; on every serial path that counter stays 0.
  ;;
  ;; This makes the screen comparison cross-implementation as well: the
  ;; concurrent path builds rows with %RENDER-ROW-SNAPSHOT and commits them via
  ;; %COMMIT-RENDER-ROW!, while EXPECTED comes from RENDER-CHIP8! via
  ;; %RENDER-DISPLAY-ROW-INTO-SCREEN!. Those are two distinct implementations,
  ;; so a divergence between them is detectable here.
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

;;; The DESCRIBE groups below exist so BEFORE-EACH reaches these tests at all.
;;; They previously sat at top level, outside any DESCRIBE, where the
;;; "render-chip8-concurrently!" suite's own BEFORE-EACH does not apply --
;;; cl-weave runs a BEFORE-EACH only for the ITs inside its enclosing DESCRIBE
;;; (see t/package.lisp's note on the hook). That left them reading whatever
;;; CPU and display state the previously-run test happened to leave behind,
;;; most visibly the SET-SOUND-TIMER! 7 that %PAINT-CONCURRENCY-PATTERN! ends
;;; with, which survives into any test that only calls DISPLAY-RESET!.

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
