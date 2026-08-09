;;;; bench/render.lisp -- deterministic baseline/concurrent render comparison.
(require :asdf)

(defun script-directory ()
  (make-pathname
   :name
   nil
   :type
   nil
   :defaults
   (or
    *load-truename*
    *compile-file-truename*
    (error "Unable to determine the script location"))))

(defun project-root ()
  (truename (merge-pathnames #p"../" (script-directory))))

(defun local-source-directories (root)
  (let ((organization-root (truename (merge-pathnames #p"../" root))))
    (loop for name in (list
                       "cl-chip8"
                       "cl-prolog"
                       "cl-tty-kit"
                       "cl-cli"
                       "cl-concurrent-kit"
                       "cl-boundary-kit"
                       "cl-date-kit"
                       "cl-host-kit"
                       "cl-codec-kit"
                       "cl-weave")
          for directory = (merge-pathnames (format nil "~A/" name) organization-root)
          when (probe-file directory)
            collect (truename directory))))

(defun configure-local-source-registry (root) (asdf:initialize-source-registry `(:source-registry ,@(mapcar (lambda (directory) `(:directory ,directory)) (local-source-directories root)) :ignore-inherited-configuration)))

(let ((root (project-root)))
  (configure-local-source-registry root)
  (asdf:load-system "cl-chip8"))

(defun positive-integer-env (name default)
  (let ((value (host-kit:getenv name))) (if value (handler-case (max 1 (parse-integer value)) (parse-error () default)) default)))

(defun monotonic-seconds ()
  (/ (get-internal-real-time) internal-time-units-per-second))

(defun paint-dense-fixture! ()
  (dotimes (y cl-chip8:+display-height+)
    (dotimes (x cl-chip8:+display-width+)
      (when (zerop (mod (+ (* x 3) y) 11))
        (setf (aref cl-chip8::*display* y x) 1)))))

(defun prepare-fixture! (dense-p)
  (cl-chip8:reset-cpu-state!)
  (cl-chip8:display-reset!)
  (when dense-p
    (paint-dense-fixture!))
  (cl-chip8::display-mark-all-dirty!))

(defun advance-fixture! (frame dirty-row-count)
  (if (= dirty-row-count (truncate cl-chip8:+display-height+ 2)) (cl-chip8::display-mark-all-dirty!)
    (dotimes (offset dirty-row-count)
      (let ((terminal-row (mod (+ frame offset) (truncate cl-chip8:+display-height+ 2))))
        (cl-chip8:display-xor-pixel!
         (mod (+ (* frame 7) (* offset 13)) cl-chip8:+display-width+)
         (* 2 terminal-row))))))

(defun render-frame! (mode screen pipeline frame dirty-row-count)
  (advance-fixture! frame dirty-row-count)
  (ecase mode
    (:baseline (cl-chip8:render-chip8! screen))
    ((:partial-serial :concurrent)
     (cl-chip8:render-chip8-concurrently! screen pipeline))))

(defun measure-render-mode (mode screen pipeline dirty-row-count warmup iterations)
  "Measure ITERATIONS after WARMUP and report measured counter deltas."
  (dotimes (frame warmup)
    (render-frame! mode screen pipeline frame dirty-row-count))
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
      (render-frame!
       mode
       screen
       pipeline
       (+ warmup frame)
       dirty-row-count))
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
  (prepare-fixture! dense-p)
  (let ((screen
         (cl-tty-kit:make-screen cl-chip8:+screen-width+ cl-chip8:+screen-height+)))
    (if (eq mode :baseline)
        (measure-render-mode
         mode
         screen
         nil
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
           pipeline
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

(let* ((warmup (positive-integer-env "CL_CHIP8_BENCH_WARMUP" 5))
       (iterations (positive-integer-env "CL_CHIP8_BENCH_ITERATIONS" 2000))
       (parallel-threshold
         (positive-integer-env "CL_CHIP8_BENCH_PARALLEL_THRESHOLD" 13))
       (parallelism
         (positive-integer-env "CL_CHIP8_BENCH_PARALLELISM" 4)))
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
  (host-kit:quit 0))
