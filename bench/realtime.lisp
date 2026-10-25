(require :asdf)
  (let* ((script-path *load-truename*)
         (root (truename
                (merge-pathnames #p"../"
                                 (uiop:pathname-directory-pathname script-path))))
         (bootstrap (merge-pathnames #p"tools/bootstrap.lisp" root)))
    (load bootstrap)
    (configure-local-source-registry root)
    (asdf:load-system "cl-chip8"))

  (defconstant +bench-ticks+ 60)
  (defconstant +bench-clock-hz+ 60000)
  (defconstant +bench-interval+ (/ 1d0 60d0))

  (defun positive-integer-env (name default)
    (let ((value (host-kit:getenv name)))
      (if value
          (handler-case (max 1 (parse-integer value))
            (parse-error () default))
          default)))

  (defun bench-audio-mode ()
    (let ((value (host-kit:getenv "CL_CHIP8_BENCH_AUDIO_MODE")))
      (cond ((null value) :off)
            ((string-equal value "off") :off)
            ((string-equal value "recording") :recording)
            (t (error "Unsupported audio mode: ~A. Use off or recording." value)))))

  (defun make-bench-rom ()
    (make-array
     55
     :element-type '(unsigned-byte 8)
     :initial-contents
     (append
      '(#x60 #x00 #x62 #x3d #xa2 #x18 #xf0 #x02 #xa2 #x28 #x61 #x00
        #xd0 #x1f #x61 #x10 #xd0 #x1f #xf2 #x18 #x61 #x00 #x12 #x0c)
      '(#xaa #x55 #xaa #x55 #xaa #x55 #xaa #x55
        #xaa #x55 #xaa #x55 #xaa #x55 #xaa #x55)
      '(#xff #xaa #x55 #xff #xaa #x55 #xff #xaa #x55
        #xff #xaa #x55 #xff #xaa #x55))))

  (defun make-bench-app (pipeline)
    (let* ((machine (cl-chip8:make-chip8-machine :platform :xo-chip))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine)
                 :renderer (cl-tty-kit:make-renderer cl-chip8:+screen-width+ cl-chip8:+screen-height+)
                 :render-state (cl-chip8::make-chip8-render-state)
                 :render-pipeline pipeline
                 :decoder (cl-tty-kit:make-input-decoder)
                 :clock-hz +bench-clock-hz+
                 :audio-mode :off
                 :started-at (get-internal-real-time))))
      (cl-chip8:load-rom machine (make-bench-rom))
      app))

  (defun monotonic-seconds ()
    (/ (get-internal-real-time) internal-time-units-per-second))

  (defun maximum (values)
    (reduce #'max values :initial-value 0d0))

  (defun run-loop (app stream)
    (let* ((machine (cl-chip8::chip8-app-machine app))
           (before (cl-chip8:chip8-machine-instructions machine))
           (ticks 0) (renders 0) (frames 0) (characters 0)
           (sound-active-ticks 0)
           (callback-start nil) (first-start nil) (last-start nil)
           (last-work nil) (last-work-end nil)
           (periods '()) (tick-latenesses '())
           (advance-times '()) (render-times '())
           (work-times '()) (post-callback-residuals '())
           (post-work-delays '()))
      (flet ((quantile-value (values quantile)
               ;; Interpolate between adjacent sorted observations for p50/p95.
               (let* ((sorted (sort (copy-list values) #'<))
                      (position (* quantile (1- (length sorted))))
                      (lower (floor position))
                      (upper (ceiling position))
                      (fraction (- position lower)))
                 (+ (nth lower sorted)
                    (* fraction (- (nth upper sorted) (nth lower sorted))))))
             (advance (state)
               (let ((now (monotonic-seconds)))
                 (when last-start
                   (let ((period (- now last-start)))
                     (push period periods)
                     (when last-work
                       ;; Residual = period - work; it includes output/flush,
                       ;; interval sleep, and loop/scheduler wake-up overhead.
                       (push (max 0d0 (- period last-work))
                             post-callback-residuals)
                       ;; Delay = max(0, next-start - max(work-end, start+interval)).
                       ;; It can include flush past the deadline, not just OS wake-up.
                       (push (max 0d0
                                  (- now
                                     (max last-work-end
                                          (+ last-start +bench-interval+))))
                             post-work-delays))))
                 (setf first-start (or first-start now))
                 (push (max 0d0
                            (- now (+ first-start (* ticks +bench-interval+))))
                       tick-latenesses)
                 (setf last-start now
                       callback-start now)
                 (let ((started now))
                   (incf ticks)
                   (cl-chip8::%advance-chip8! state)
                   (push (- (monotonic-seconds) started) advance-times))
                 (when (plusp (cl-chip8:chip8-machine-sound-timer machine))
                   (incf sound-active-ticks))
                 state))
             (render (state)
               (let* ((started (monotonic-seconds))
                      (frame (cl-chip8::%render-chip8-app! state))
                      (rendered (monotonic-seconds)))
                 (incf renders)
                 (when (and (stringp frame) (plusp (length frame)))
                   (incf frames)
                   (incf characters (length frame)))
                 (push (- rendered started) render-times)
                 (setf last-work-end (monotonic-seconds)
                       last-work (- last-work-end callback-start))
                 (push last-work work-times)
                 frame))
             (stop (state)
               (declare (ignore state))
               (>= ticks +bench-ticks+)))
        (let ((started (monotonic-seconds)))
          (cl-tty-kit:tick-loop-run-realtime
           app #'advance #'render #'stop
           :stream stream :interval +bench-interval+)
          (let* ((wall-elapsed (- (monotonic-seconds) started))
                 (instructions
                   (- (cl-chip8:chip8-machine-instructions machine) before))
                 (max-period (maximum periods))
                 (scheduled-window (* +bench-ticks+ +bench-interval+))
                 (frame-window
                   (+ (- last-start first-start) +bench-interval+))
                 (tick-rate (/ ticks frame-window))
                 (p50-lateness (quantile-value tick-latenesses 0.50d0))
                 (p95-lateness (quantile-value tick-latenesses 0.95d0))
                 (max-lateness (maximum tick-latenesses)))
            (unless (and (= ticks +bench-ticks+)
                         (= renders +bench-ticks+)
                         (= instructions +bench-clock-hz+)
                         (= (length tick-latenesses) +bench-ticks+)
                         (plusp frames)
                         (null (cl-chip8::chip8-app-error app)))
              (error "Incomplete trial: ticks=~D renders=~D instructions=~D."
                     ticks renders instructions))
            (list :ticks ticks :renders renders :frames frames
                  :characters characters :instructions instructions
                  :wall-elapsed wall-elapsed
                  :wall-rate (/ instructions wall-elapsed)
                  :scheduled-window scheduled-window
                  :frame-window frame-window
                  :tick-rate tick-rate
                  :period-count (length periods)
                  :period-overruns
                  (count-if (lambda (seconds)
                              (> seconds +bench-interval+))
                            periods)
                  :max-period max-period
                  :p50-lateness p50-lateness
                  :p95-lateness p95-lateness
                  :max-lateness max-lateness
                  :work-overruns
                  (count-if (lambda (seconds)
                              (> seconds +bench-interval+))
                            work-times)
                  :max-work (maximum work-times)
                  :max-advance (maximum advance-times)
                  :max-render (maximum render-times)
                  :max-post-callback-residual (maximum post-callback-residuals)
                  :max-post-work-delay (maximum post-work-delays)
                  :sound-active-ticks sound-active-ticks
                  :sound-timer
                  (cl-chip8:chip8-machine-sound-timer machine)))))))

  (defun run-output (app)
    (if (and (interactive-stream-p *standard-input*)
             (interactive-stream-p *standard-output*))
        (let ((result nil))
          (cl-tty-kit:with-terminal-session
              (stream :stream *standard-output* :fd 0 :raw-mode t
                      :alternate-screen t :hide-cursor t)
            (setf (cl-chip8::chip8-app-stream app) stream)
            (setf result (run-loop app stream)))
          (values result :tty nil))
        (let ((result nil) (captured nil))
          (setf captured
                (with-output-to-string (stream)
                  (setf (cl-chip8::chip8-app-stream app) stream)
                  (setf result (run-loop app stream))))
          (values result :string (length captured)))))

  (defun run-trial (label requested-audio)
    (unless (member requested-audio '(:off :recording))
      (error "Unsupported benchmark audio mode: ~A" requested-audio))
    (cl-chip8:with-chip8-render-pipeline (pipeline)
      (let* ((app (make-bench-app pipeline))
             (audio-stream nil) (recording-device nil) (audio-output nil)
             (audio-mode nil)
             (pcm-frames 0) (nonzero-pcm-samples 0)
             (recorded-chunks nil) (recorded-blocks 0) (recorded-frames 0)
             (audio-worker-failure nil) (result nil)
             (sink nil) (captured nil)
             (audio-writer
               (let ((deadline nil))
                 (lambda (stream samples)
                   (let ((written (cl-audio-kit:write-frames stream samples)))
                     (when (= written (length samples))
                       (incf nonzero-pcm-samples
                             (count-if (lambda (sample) (not (zerop sample)))
                                       samples)))
                     (setf deadline
                           (+ (or deadline (monotonic-seconds))
                              (/ written cl-chip8::+audio-sample-rate+)))
                     (loop for remaining = (- deadline (monotonic-seconds))
                           while (plusp remaining)
                           do (sleep remaining))
                     written)))))
        (if (eq requested-audio :recording)
            (setf audio-mode :recording
                  recording-device (cl-audio-kit:make-recording-device)
                  audio-stream
                  (cl-audio-kit:open-output-stream
                   :sample-rate cl-chip8::+audio-sample-rate+
                   :channels 1
                   :sample-format :float32
                   :device recording-device)
                  (cl-chip8::chip8-app-audio-mode app) :pcm)
            (setf audio-mode :off
                  (cl-chip8::chip8-app-audio-mode app) :off))
        (when (eq audio-mode :recording)
          (setf audio-output
                (cl-chip8::start-chip8-audio-output
                 audio-stream
                 (cl-chip8::chip8-app-machine app)
                 :writer audio-writer)
                audio-stream nil
                (cl-chip8::chip8-app-audio-output app) audio-output))
        (unwind-protect
             (multiple-value-setq (result sink captured)
               (run-output app))
          (when audio-output
            (cl-chip8::stop-chip8-audio-output! audio-output)
            (setf pcm-frames
                  (sb-thread:with-mutex
                      ((cl-chip8::chip8-audio-output-lock audio-output))
                    (cl-chip8::chip8-audio-output-frames-written
                     audio-output)))
            (setf audio-worker-failure
                  (cl-chip8::chip8-audio-output-failure audio-output)))
          (when recording-device
            (setf recorded-chunks
                  (cl-audio-kit:recorded-samples recording-device)
                  recorded-blocks (length recorded-chunks)
                  recorded-frames
                  (reduce #'+ recorded-chunks :key #'length :initial-value 0)
                  nonzero-pcm-samples
                  (loop for samples in recorded-chunks
                        sum (count-if
                             (lambda (sample) (not (zerop sample)))
                             samples))))
          (when audio-stream
            (cl-audio-kit:close-output-stream audio-stream)))
        (when audio-worker-failure
          (error "Audio worker failed: ~A" audio-worker-failure))
        (let* ((within-schedule
                 (<= (getf result :wall-elapsed)
                     (getf result :scheduled-window)))
               (within-frame-window
                 (<= (getf result :frame-window)
                     (getf result :scheduled-window)))
               (tick-rate-met (>= (getf result :tick-rate) 60d0))
               (max-lateness-met
                 (<= (getf result :max-lateness) +bench-interval+)))
          (append result
                  (list :label label :audio-mode audio-mode
                        :audio-device
                        (if (eq audio-mode :recording) "RECORDING" "NONE")
                        :audio-model
                        (if (eq audio-mode :recording)
                            "PACED-480-FRAMES/10MS;NO-HARDWARE-CONSUMPTION"
                            "NONE")
                        :portaudio "NO"
                        :pcm-frames pcm-frames
                        :nonzero-pcm-samples nonzero-pcm-samples
                        :recorded-blocks recorded-blocks
                        :recorded-frames recorded-frames
                        :audio-worker-failure nil
                        :sink sink
                        :captured-characters captured
                        :within-schedule within-schedule
                        :within-frame-window within-frame-window
                        :tick-rate-met tick-rate-met
                        :max-lateness-met max-lateness-met
                        :target-met
                        (and (eq sink :tty)
                             (eq audio-mode :recording)
                             (plusp (getf result :frames))
                             (plusp pcm-frames)
                             (plusp recorded-blocks)
                             (plusp recorded-frames)
                             (plusp nonzero-pcm-samples)
                             (= (getf result :sound-active-ticks)
                                +bench-ticks+)
                             tick-rate-met
                             max-lateness-met)))))))

  (defun print-trial (result)
    (format
     t
     "~&~A target=~A audio=~A audio-device=~A audio-model=~A portaudio=~A sink=~A instructions=~D ticks=~D renders=~D changed-frames=~D output-chars=~D wall-elapsed=~,6Fs wall-rate=~D/s tick-rate=~,2F/s scheduled-window=~,6Fs frame-window=~,6Fs periods=~D period-overruns=~D max-period=~,6Fs p50-lateness=~,6Fs p95-lateness=~,6Fs max-lateness=~,6Fs work-overruns=~D max-work=~,6Fs max-advance=~,6Fs max-render=~,6Fs post-callback-residual=~,6Fs post-work-delay=~,6Fs pcm-frames=~D nonzero-pcm-samples=~D recorded-blocks=~D recorded-frames=~D sound-active-ticks=~D audio-worker-failure=~A within-schedule=~A within-frame-window=~A tick-rate-met=~A max-lateness-met=~A sound-timer=~D~%"
     (getf result :label)
     (if (getf result :target-met) "MET" "NOT-MET")
     (string-upcase (symbol-name (getf result :audio-mode)))
     (getf result :audio-device)
     (getf result :audio-model)
     (getf result :portaudio)
     (string-upcase (symbol-name (getf result :sink)))
     (getf result :instructions) (getf result :ticks)
     (getf result :renders) (getf result :frames) (getf result :characters)
     (getf result :wall-elapsed) (truncate (getf result :wall-rate))
     (getf result :tick-rate) (getf result :scheduled-window)
     (getf result :frame-window) (getf result :period-count)
     (getf result :period-overruns) (getf result :max-period)
     (getf result :p50-lateness) (getf result :p95-lateness)
     (getf result :max-lateness) (getf result :work-overruns)
     (getf result :max-work) (getf result :max-advance)
     (getf result :max-render) (getf result :max-post-callback-residual)
     (getf result :max-post-work-delay)
     (getf result :pcm-frames) (getf result :nonzero-pcm-samples)
     (getf result :recorded-blocks) (getf result :recorded-frames)
     (getf result :sound-active-ticks)
     (getf result :audio-worker-failure)
     (if (getf result :within-schedule) "YES" "NO")
     (if (getf result :within-frame-window) "YES" "NO")
     (if (getf result :tick-rate-met) "YES" "NO")
     (if (getf result :max-lateness-met) "YES" "NO")
     (getf result :sound-timer)))

  (defun median-value (values)
    (let* ((sorted (sort (copy-list values) #'<))
           (count (length sorted))
           (middle (floor count 2)))
      (if (oddp count) (nth middle sorted)
          (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2d0))))

  (defun main ()
    (let* ((warmups (positive-integer-env "CL_CHIP8_BENCH_WARMUP" 1))
           (runs (positive-integer-env "CL_CHIP8_BENCH_RUNS" 3))
           (audio (bench-audio-mode))
           (report-only
             (let ((value (host-kit:getenv "CL_CHIP8_BENCH_REPORT_ONLY")))
               (cond ((null value) nil)
                     ((string-equal value "0") nil)
                     ((string-equal value "1") t)
                     (t (error "Unsupported report-only value: ~A" value)))))
           (results '()))
      (format t "~&P5 realtime: clock_hz=60000 target=XO-CHIP+1000-INSTRUCTIONS/TICK+60-TICKS+TTY+RECORDING+NONZERO-SAMPLE+WORKER-OK+SOUND-ACTIVE=60+AVG-TICK-RATE>=60+MAX-LATENESS<=FRAME, warmup=~D runs=~D audio-request=~A report-only=~A recording-model=PACED-480-FRAMES/10MS;NO-HARDWARE-CONSUMPTION~%"
              warmups runs (string-upcase (symbol-name audio))
              (if report-only "YES" "NO"))
      (dotimes (index warmups)
        (run-trial (format nil "WARMUP-~D" (1+ index)) audio))
      (dotimes (index runs)
        (let ((result (run-trial (format nil "RUN-~D" (1+ index)) audio)))
          (push result results)
          (print-trial result)))
      (setf results (nreverse results))
      (format t "~&SUMMARY runs=~D median-wall-elapsed=~,6Fs median-wall-rate=~D/s median-tick-rate=~,2F/s median-p50-lateness=~,6Fs median-p95-lateness=~,6Fs max-lateness=~,6Fs max-period-overruns=~D/~D sound-active-ticks-min=~D max=~D nonzero-pcm-runs=~D/~D audio-worker-failures=~D within-schedule-runs=~D/~D within-frame-window-runs=~D/~D tick-rate-met-runs=~D/~D max-lateness-met-runs=~D/~D target-runs=~D/~D~%"
              runs
              (median-value (mapcar (lambda (r) (getf r :wall-elapsed)) results))
              (truncate (median-value
                         (mapcar (lambda (r) (getf r :wall-rate)) results)))
              (median-value (mapcar (lambda (r) (getf r :tick-rate)) results))
              (median-value (mapcar (lambda (r) (getf r :p50-lateness)) results))
              (median-value (mapcar (lambda (r) (getf r :p95-lateness)) results))
              (maximum (mapcar (lambda (r) (getf r :max-lateness)) results))
              (reduce #'max results :key (lambda (r) (getf r :period-overruns))
                      :initial-value 0)
              (getf (first results) :period-count)
              (reduce #'min results
                      :key (lambda (r) (getf r :sound-active-ticks))
                      :initial-value +bench-ticks+)
              (reduce #'max results
                      :key (lambda (r) (getf r :sound-active-ticks))
                      :initial-value 0)
              (count-if (lambda (r) (plusp (getf r :nonzero-pcm-samples)))
                        results)
              runs
              (count-if (lambda (r) (getf r :audio-worker-failure)) results)
              (count-if (lambda (r) (getf r :within-schedule)) results)
              runs
              (count-if (lambda (r) (getf r :within-frame-window)) results)
              runs
              (count-if (lambda (r) (getf r :tick-rate-met)) results)
              runs
              (count-if (lambda (r) (getf r :max-lateness-met)) results)
              runs
              (count-if (lambda (r) (getf r :target-met)) results)
              runs)
      (finish-output)
      (host-kit:quit (if (or report-only
                             (every (lambda (r) (getf r :target-met)) results))
                         0
                         1))))

  (main)
