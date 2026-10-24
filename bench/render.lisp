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
  (let ((height (array-dimension framebuffer 0))
        (width (array-dimension framebuffer 1)))
    (dotimes (y height)
      (dotimes (x width)
        (when (zerop (mod (+ (* x 3) y) 11))
          (setf (aref framebuffer y x) 1))))))

(defun prepare-fixture! (resolution dense-p)
  (let ((machine
          (cl-chip8:make-chip8-machine
           :platform (if (eq resolution :hires) :schip :modern))))
    (when (eq resolution :hires)
      (cl-chip8:set-chip8-machine-resolution! machine :hires))
    (let ((framebuffer (cl-chip8:chip8-framebuffer machine)))
      (when dense-p
        (paint-dense-fixture! framebuffer))
      framebuffer)))

(defun advance-fixture! (framebuffer frame dirty-row-count mode)
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (source-rows-per-cell
           (ecase mode
             (:lores 2)
             (:half-block 2)
             (:quarter-block 2)
             (:braille 4)))
         (terminal-row-count (ceiling height source-rows-per-cell)))
    (dotimes (offset dirty-row-count)
      (let ((terminal-row (mod (+ frame offset) terminal-row-count))
            (x (mod (+ (* frame 7) (* offset 13)) width)))
        (dotimes (source-row source-rows-per-cell)
          (let ((y (+ (* terminal-row source-rows-per-cell) source-row)))
            (when (< y height)
              (setf (aref framebuffer y x)
                    (logxor 1 (aref framebuffer y x))))))))))

(defun render-frame!
    (render-mode display-mode screen framebuffer pipeline state frame dirty-row-count)
  (advance-fixture! framebuffer frame dirty-row-count display-mode)
  (ecase render-mode
    (:baseline
     (cl-chip8:render-chip8! screen framebuffer state :mode display-mode))
    ((:partial-serial :concurrent)
     (cl-chip8:render-chip8-concurrently!
      screen framebuffer pipeline :mode display-mode))))

(defun measure-render-mode
    (render-mode display-mode screen framebuffer pipeline state dirty-row-count
     warmup iterations)
  "Measure ITERATIONS after WARMUP and report measured counter deltas."
  (dotimes (frame warmup)
    (render-frame! render-mode display-mode screen framebuffer pipeline state
                   frame dirty-row-count))
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
      (render-frame! render-mode display-mode screen framebuffer pipeline state
                     (+ warmup frame) dirty-row-count))
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

(defun run-mode
    (render-mode resolution display-mode dense-p dirty-row-count warmup iterations
     parallel-threshold parallelism)
  (multiple-value-bind (screen-width screen-height)
      (ecase display-mode
        (:lores (values 66 18))
        (:half-block (values 130 34))
        (:quarter-block (values 66 34))
        (:braille (values 66 18)))
    (let ((framebuffer (prepare-fixture! resolution dense-p))
          (screen (cl-tty-kit:make-screen screen-width screen-height))
          (state (cl-chip8::make-chip8-render-state)))
      (if (eq render-mode :baseline)
          (measure-render-mode
           render-mode display-mode screen framebuffer nil state
           dirty-row-count warmup iterations)
          (cl-chip8:with-chip8-render-pipeline
              (pipeline
               :parallelism parallelism
               :parallel-threshold
               (if (eq render-mode :partial-serial)
                   most-positive-fixnum
                   parallel-threshold))
            (measure-render-mode
             render-mode display-mode screen framebuffer pipeline state
             dirty-row-count warmup iterations))))))

(defun screens-equal-p (left right)
  (and (= (cl-tty-kit:screen-width left)
          (cl-tty-kit:screen-width right))
       (= (cl-tty-kit:screen-height left)
          (cl-tty-kit:screen-height right))
       (loop for y below (cl-tty-kit:screen-height left)
             always
             (loop for x below (cl-tty-kit:screen-width left)
                   for left-cell = (cl-tty-kit:screen-cell left x y)
                   for right-cell = (cl-tty-kit:screen-cell right x y)
                   always
                   (and (eql (cl-tty-kit:cell-char left-cell)
                             (cl-tty-kit:cell-char right-cell))
                        (equal (cl-tty-kit:cell-style left-cell)
                               (cl-tty-kit:cell-style right-cell)))))))

(defun print-comparison
    (label display-mode baseline concurrent warmup iterations parallel-threshold
     parallelism)
  (unless (screens-equal-p (getf baseline (quote :screen))
                           (getf concurrent (quote :screen)))
    (error "Renderer output differs for ~A fixture." label))
  (let* ((baseline-seconds (getf baseline (quote :seconds)))
         (concurrent-seconds (getf concurrent (quote :seconds)))
         (speedup
           (/ baseline-seconds
              (max concurrent-seconds least-positive-double-float))))
    (format
     t
     "~&~A mode=~A (threshold=~D, parallelism=~D, ~D warmup, ~D measured): baseline=~,6Fs concurrent=~,6Fs speedup=~,2Fx submitted=~D completed=~D serial=~D queue-high-water=~D~%"
     label display-mode parallel-threshold parallelism warmup iterations
     baseline-seconds concurrent-seconds speedup
     (getf concurrent (quote :submitted))
     (getf concurrent (quote :completed))
     (getf concurrent (quote :serial))
     (getf concurrent (quote :high-water-mark)))))

(defun print-partial-comparison
    (label display-mode serial-partial selected warmup iterations
     parallel-threshold parallelism)
  (unless (screens-equal-p (getf serial-partial (quote :screen))
                           (getf selected (quote :screen)))
    (error "Partial renderer output differs for ~A fixture." label))
  (let* ((serial-seconds (getf serial-partial (quote :seconds)))
         (selected-seconds (getf selected (quote :seconds)))
         (selected-speedup
           (/ serial-seconds
              (max selected-seconds least-positive-double-float))))
    (format
     t
     "~&~A partial mode=~A (threshold=~D, parallelism=~D, ~D warmup, ~D measured): forced-serial=~,6Fs selected=~,6Fs selected-speedup=~,2Fx submitted=~D completed=~D serial-rows=~D queue-high-water=~D~%"
     label display-mode parallel-threshold parallelism warmup iterations
     serial-seconds selected-seconds selected-speedup
     (getf selected (quote :submitted))
     (getf selected (quote :completed))
     (getf selected (quote :serial))
     (getf selected (quote :high-water-mark)))))

(sb-ext:with-timeout 600
  (let* ((warmup (positive-integer-env "CL_CHIP8_BENCH_WARMUP" 5))
         (iterations
           (positive-integer-env "CL_CHIP8_BENCH_ITERATIONS" 2000))
         (parallel-threshold
           (positive-integer-env "CL_CHIP8_BENCH_PARALLEL_THRESHOLD" 13))
         (parallelism
           (positive-integer-env
            "CL_CHIP8_BENCH_PARALLELISM"
            cl-chip8::+concurrent-render-default-parallelism+)))
    (format
     t
     "~&P0.1 reference: 64x32 lores, five fixtures, 5 warmups, 2000 measured frames, 8 workers; the single 4.09s total run was unreliable under high/unattributed load.~%")
    (dolist
        (fixture
         '((:sparse :lores :lores nil 1)
           (:medium :lores :lores nil 8)
           (:large-partial :lores :lores nil 12)
           (:worker-partial :lores :lores nil 15)
           (:dense :lores :lores t 16)
           (:hires-half-sparse :hires :half-block nil 1)
           (:hires-half-worker-partial :hires :half-block nil 27)
           (:hires-quarter-worker-partial :hires :quarter-block nil 27)
           (:hires-braille-worker-partial :hires :braille nil 15)
           (:hires-half-dense :hires :half-block t 32)))
      (destructuring-bind
          (name resolution display-mode dense-p dirty-row-count)
          fixture
        (let* ((label (string-upcase (symbol-name name)))
               (row-count
                 (ecase display-mode
                   (:lores 16)
                   (:half-block 32)
                   (:quarter-block 32)
                   (:braille 16)))
               (mode-threshold
                 (ceiling
                  (* row-count parallel-threshold)
                  cl-chip8::+concurrent-render-reference-row-count+))
               (minimum-snapshot-count
                 (ceiling
                  (* row-count cl-chip8::+concurrent-render-minimum-snapshots+)
                  cl-chip8::+concurrent-render-reference-row-count+))
               (baseline
                 (run-mode
                  :baseline resolution display-mode dense-p dirty-row-count
                  warmup iterations mode-threshold parallelism))
               (serial-partial
                 (run-mode
                  :partial-serial resolution display-mode dense-p dirty-row-count
                  warmup iterations mode-threshold parallelism))
               (concurrent
                 (run-mode
                  :concurrent resolution display-mode dense-p dirty-row-count
                  warmup iterations mode-threshold parallelism)))
          (print-comparison
           label display-mode baseline concurrent warmup iterations
           mode-threshold parallelism)
          (print-partial-comparison
           label display-mode serial-partial concurrent warmup iterations
           mode-threshold parallelism)
          (when (and (>= dirty-row-count mode-threshold)
                     (>= dirty-row-count minimum-snapshot-count)
                     (< dirty-row-count row-count)
                     (zerop (getf concurrent (quote :submitted))))
            (error "~A fixture did not submit any worker rows." label)))))
    (host-kit:quit 0)))
