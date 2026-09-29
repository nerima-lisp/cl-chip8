;;;; bench/render.lisp -- deterministic baseline/concurrent render comparison.
(require :asdf)

(let* ((script-path *load-truename*)
       (project-root (truename
                      (merge-pathnames #p"../"
                                       (uiop:pathname-directory-pathname script-path))))
       (bootstrap (merge-pathnames #p"tools/bootstrap.lisp" project-root)))
  (load bootstrap)
  (let ((root (truename project-root)))
  (configure-local-source-registry root)
    (asdf:load-system "cl-chip8")))

(defun positive-integer-env (name default)
  (let ((value (host-kit:getenv name))) (if value (handler-case (max 1 (parse-integer value)) (parse-error () default)) default)))

(defun monotonic-seconds ()
  (/ (get-internal-real-time) internal-time-units-per-second))

(defun paint-dense-fixture! (framebuffer)
  (dotimes (y cl-chip8:+display-height+)
    (dotimes (x cl-chip8:+display-width+)
      (when (zerop (mod (+ (* x 3) y) 11))
        (setf (aref framebuffer y x) 1)))))

(defun prepare-fixture! (dense-p)
  (let ((machine (cl-chip8:make-chip8-machine)))
    (let ((framebuffer (cl-chip8:chip8-framebuffer machine)))
      (when dense-p
        (paint-dense-fixture! framebuffer))
      framebuffer)))

(defun advance-fixture! (framebuffer frame dirty-row-count)
  (dotimes (offset dirty-row-count)
    (let ((terminal-row (mod (+ frame offset) (truncate cl-chip8:+display-height+ 2)))
          (x (mod (+ (* frame 7) (* offset 13)) cl-chip8:+display-width+)))
      (dotimes (scanline 2)
        (let ((y (+ (* 2 terminal-row) scanline)))
          (setf (aref framebuffer y x) (logxor 1 (aref framebuffer y x))))))))

(defun render-frame! (mode screen framebuffer pipeline state frame dirty-row-count)
  (advance-fixture! framebuffer frame dirty-row-count)
  (ecase mode
    (:baseline (cl-chip8:render-chip8! screen framebuffer state))
    ((:partial-serial :concurrent)
     (cl-chip8:render-chip8-concurrently! screen framebuffer pipeline))))

(defun measure-render-mode (mode screen framebuffer pipeline state dirty-row-count warmup iterations)
  "Measure ITERATIONS after WARMUP and report measured counter deltas."
  (dotimes (frame warmup)
    (render-frame! mode screen framebuffer pipeline state frame dirty-row-count))
  (let* ((submitted-before
           (if pipeline
               (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
               0))
         (completed-before
           (if pipeline
               (cl-chip8::chip8-render-pipeline-completed-rows pipeline)
               0))
         (serial-before
           (if pipeline
               (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
               0))
         (started-at (monotonic-seconds)))
    (dotimes (frame iterations)
      (render-frame! mode screen framebuffer pipeline state (+ warmup frame) dirty-row-count))
    (list
     :seconds
     (- (monotonic-seconds) started-at)
     :screen
     screen
     :submitted
     (- (if pipeline
            (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
            0)
        submitted-before)
     :completed
     (- (if pipeline
            (cl-chip8::chip8-render-pipeline-completed-rows pipeline)
            0)
        completed-before)
     :serial
     (- (if pipeline
            (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
            0)
        serial-before)
     :high-water-mark
     (if pipeline
         (cl-chip8::chip8-render-pipeline-high-water-mark pipeline)
         0))))

(defun run-mode (mode dense-p dirty-row-count warmup iterations parallel-threshold parallelism)
  (let ((framebuffer (prepare-fixture! dense-p))
        (screen
         (cl-tty-kit:make-screen cl-chip8:+screen-width+ cl-chip8:+screen-height+))
        (state (cl-chip8::make-chip8-render-state)))
    (if (eq mode :baseline)
        (measure-render-mode
         mode
         screen
         framebuffer
         nil
         state
         dirty-row-count
         warmup
         iterations)
        (cl-chip8:with-chip8-render-pipeline
            (pipeline
             :parallelism parallelism
             :parallel-threshold
             (if (eq mode :partial-serial)
                 most-positive-fixnum
                 parallel-threshold))
          (measure-render-mode
           mode
           screen
           framebuffer
           pipeline
           state
           dirty-row-count
           warmup
           iterations)))))

(defun screens-equal-p (left right)
  (loop for y below cl-chip8:+screen-height+
        always (loop for x below cl-chip8:+screen-width+
                     for left-cell = (cl-tty-kit:screen-cell left x y)
                     for right-cell = (cl-tty-kit:screen-cell right x y)
                     always (and
                             (eql
                              (cl-tty-kit:cell-char left-cell)
                              (cl-tty-kit:cell-char right-cell))
                             (equal
                              (cl-tty-kit:cell-style left-cell)
                              (cl-tty-kit:cell-style right-cell))))))

(defun print-comparison (label baseline concurrent warmup iterations parallel-threshold parallelism)
  (unless (screens-equal-p (getf baseline (quote :screen)) (getf concurrent (quote :screen)))
    (error "Renderer output differs for ~A fixture." label))
  (let* ((baseline-seconds (getf baseline (quote :seconds)))
         (concurrent-seconds (getf concurrent (quote :seconds)))
         (speedup
          (/ baseline-seconds (max concurrent-seconds least-positive-double-float))))
    (format
     t
     "~&~A (threshold=~D, parallelism=~D, ~D warmup, ~D measured): baseline=~,6Fs concurrent=~,6Fs speedup=~,2Fx submitted=~D completed=~D serial=~D queue-high-water=~D~%"
     label
     parallel-threshold
     parallelism
     warmup
     iterations
     baseline-seconds
     concurrent-seconds
     speedup
     (getf concurrent (quote :submitted))
     (getf concurrent (quote :completed))
     (getf concurrent (quote :serial))
     (getf concurrent (quote :high-water-mark)))))

(defun print-partial-comparison
    (label serial-partial selected warmup iterations parallel-threshold parallelism)
  (unless
      (screens-equal-p
       (getf serial-partial (quote :screen))
       (getf selected (quote :screen)))
    (error "Partial renderer output differs for ~A fixture." label))
  (let* ((serial-seconds (getf serial-partial (quote :seconds)))
         (selected-seconds (getf selected (quote :seconds)))
         (selected-speedup
           (/ serial-seconds
              (max selected-seconds least-positive-double-float))))
    (format
     t
     "~&~A partial (threshold=~D, parallelism=~D, ~D warmup, ~D measured): forced-serial=~,6Fs selected=~,6Fs selected-speedup=~,2Fx submitted=~D completed=~D serial-rows=~D queue-high-water=~D~%"
     label
     parallel-threshold
     parallelism
     warmup
     iterations
     serial-seconds
     selected-seconds
     selected-speedup
     (getf selected (quote :submitted))
     (getf selected (quote :completed))
     (getf selected (quote :serial))
     (getf selected (quote :high-water-mark)))))

(sb-ext:with-timeout 600
  (let* ((warmup (positive-integer-env "CL_CHIP8_BENCH_WARMUP" 5))
       (iterations (positive-integer-env "CL_CHIP8_BENCH_ITERATIONS" 2000))
       (parallel-threshold
         (positive-integer-env "CL_CHIP8_BENCH_PARALLEL_THRESHOLD" 13))
       (parallelism
         (positive-integer-env
          "CL_CHIP8_BENCH_PARALLELISM"
          cl-chip8::+concurrent-render-default-parallelism+)))
  (dolist (fixture
           (quote ((:sparse nil 1)
                   (:medium nil 8)
                   (:large-partial nil 12)
                   (:dense t 16))))
    (destructuring-bind (name dense-p dirty-row-count) fixture
      (let ((label (string-upcase (symbol-name name)))
            (baseline
             (run-mode
              :baseline
              dense-p
              dirty-row-count
              warmup
              iterations
              parallel-threshold
              parallelism))
            (serial-partial
             (run-mode
              :partial-serial
              dense-p
              dirty-row-count
              warmup
              iterations
              parallel-threshold
              parallelism))
            (concurrent
             (run-mode
              :concurrent
              dense-p
              dirty-row-count
              warmup
              iterations
              parallel-threshold
              parallelism)))
        (print-comparison
         label
         baseline
         concurrent
         warmup
         iterations
         parallel-threshold
         parallelism)
        (print-partial-comparison
         label
         serial-partial
         concurrent
         warmup
         iterations
         parallel-threshold
         parallelism)
        (when
            (and
             (member name (quote (:medium :large-partial)))
             (>= dirty-row-count
                 cl-chip8::+concurrent-render-minimum-snapshots+)
             (<= parallel-threshold dirty-row-count)
             (zerop (getf concurrent (quote :submitted))))
          (error "~A fixture did not submit any worker rows." label)))))
    (host-kit:quit 0)))
