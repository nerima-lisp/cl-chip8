(progn
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
      (cond ((null value) :auto)
            ((string-equal value "auto") :auto)
            ((string-equal value "pcm") :pcm)
            ((string-equal value "bell") :bell)
            ((string-equal value "off") :off)
            (t (error "Unsupported audio mode: ~A" value)))))

  (defun make-bench-rom ()
    (make-array 35 :element-type '(unsigned-byte 8)
      :initial-contents
      '(#x60 #x00 #x62 #x3d #xa2 #x14 #x61 #x00
        #xd0 #x1f #x61 #x10 #xd0 #x1f #xf2 #x18
        #x61 #x00 #x12 #x08
        #xff #xaa #x55 #xff #xaa #x55 #xff #xaa #x55
        #xff #xaa #x55 #xff #xaa #x55)))

  (defun make-bench-app (pipeline)
    (let* ((machine (cl-chip8:make-chip8-machine :platform :schip))
           (app (cl-chip8::make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine)
                 :renderer (cl-chip8:make-renderer
                            cl-chip8:+screen-width+ cl-chip8:+screen-height+)
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
           (periods '()) (work-times '()))
      (flet ((advance (state)
               (let ((now (monotonic-seconds)))
                 (when last-start (push (- now last-start) periods))
                 (setf first-start (or first-start now)
                       last-start now
                       callback-start now)
                 (incf ticks)
                 (cl-chip8::%advance-chip8! state)
                 (when (plusp (cl-chip8:chip8-machine-sound-timer machine))
                   (incf sound-active-ticks))
                 state))
             (render (state)
               (let ((frame (cl-chip8::%render-chip8-app! state)))
                 (incf renders)
                 (when (and (stringp frame) (plusp (length frame)))
                   (incf frames)
                   (incf characters (length frame)))
                 (push (- (monotonic-seconds) callback-start) work-times)
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
                   (+ (- last-start first-start) +bench-interval+)))
            (unless (and (= ticks +bench-ticks+)
                         (= renders +bench-ticks+)
                         (= instructions +bench-clock-hz+)
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
                  :measured-frame-rate (/ instructions frame-window)
                  :target-frame-rate +bench-clock-hz+
                  :period-count (length periods)
                  :period-misses
                  (count-if (lambda (seconds)
                              (> seconds +bench-interval+))
                            periods)
                  :max-period max-period
                  :max-lateness (max 0d0 (- max-period +bench-interval+))
                  :work-overruns
                  (count-if (lambda (seconds)
                              (> seconds +bench-interval+))
                            work-times)
                  :max-work (maximum work-times)
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
    (cl-chip8:with-chip8-render-pipeline (pipeline)
      (let* ((app (make-bench-app pipeline))
             (audio-stream nil) (audio-output nil)
             (audio-mode nil) (fallback nil)
             (pcm-frames 0) (result nil)
             (sink nil) (captured nil))
        (multiple-value-setq (audio-mode audio-stream)
          (cl-chip8::%resolve-chip8-audio-mode
           requested-audio
           :on-fallback
           (lambda (condition) (setf fallback (princ-to-string condition)))))
        (setf (cl-chip8::chip8-app-audio-mode app) audio-mode)
        (when (eq audio-mode :pcm)
          (setf audio-output
                (cl-chip8::start-chip8-audio-output
                 audio-stream
                 :sound-timer
                 (cl-chip8:chip8-machine-sound-timer
                  (cl-chip8::chip8-app-machine app)))
                audio-stream nil
                (cl-chip8::chip8-app-audio-output app) audio-output))
        (unwind-protect
             (multiple-value-setq (result sink captured)
               (run-output app))
          (when audio-output
            (setf pcm-frames
                  (cl-chip8::chip8-audio-output-frames-written audio-output))
            (cl-chip8::stop-chip8-audio-output! audio-output))
          (when audio-stream
            (cl-audio-kit:close-output-stream audio-stream)))
        (when fallback
          (format *error-output* "~&Audio fallback: ~A~%" fallback))
        (let* ((within-schedule
                 (<= (getf result :wall-elapsed)
                     (getf result :scheduled-window)))
               (within-frame-window
                 (<= (getf result :frame-window)
                     (getf result :scheduled-window))))
          (append result
                  (list :label label :audio-mode audio-mode
                        :fallback (not (null fallback))
                        :pcm-frames pcm-frames :sink sink
                        :captured-characters captured
                        :within-schedule within-schedule
                        :within-frame-window within-frame-window
                        :target-met
                        (and (eq sink :tty)
                             (eq audio-mode :pcm)
                             (plusp pcm-frames)
                             (= (getf result :sound-active-ticks)
                                +bench-ticks+)
                             (zerop (getf result :period-misses))
                             within-schedule
                             within-frame-window)))))))

  (defun print-trial (result)
    (format
     t
     "~&~A target=~A audio=~A sink=~A instructions=~D ticks=~D renders=~D changed-frames=~D output-chars=~D wall-elapsed=~,6Fs wall-rate=~D/s scheduled-window=~,6Fs frame-window=~,6Fs measured-frame-rate=~D/s target-frame-rate=~D/s periods=~D misses=~D max-period=~,6Fs lateness=~,6Fs work-overruns=~D max-work=~,6Fs pcm-frames=~D sound-active-ticks=~D within-schedule=~A within-frame-window=~A sound-timer=~D~%"
     (getf result :label)
     (if (getf result :target-met) "MET" "NOT-MET")
     (string-upcase (symbol-name (getf result :audio-mode)))
     (string-upcase (symbol-name (getf result :sink)))
     (getf result :instructions) (getf result :ticks)
     (getf result :renders) (getf result :frames) (getf result :characters)
     (getf result :wall-elapsed) (truncate (getf result :wall-rate))
     (getf result :scheduled-window) (getf result :frame-window)
     (truncate (getf result :measured-frame-rate))
     (getf result :target-frame-rate)
     (getf result :period-count) (getf result :period-misses)
     (getf result :max-period) (getf result :max-lateness)
     (getf result :work-overruns) (getf result :max-work)
     (getf result :pcm-frames) (getf result :sound-active-ticks)
     (if (getf result :within-schedule) "YES" "NO")
     (if (getf result :within-frame-window) "YES" "NO")
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
           (audio (bench-audio-mode)) (results '()))
      (format t "~&P5 realtime: clock_hz=60000 tickrate=1000, 60 ticks, target=TTY+PCM+60-SOUND-TICKS+NO-MISSES+WITHIN-SCHEDULE, warmup=~D runs=~D audio-request=~A~%"
              warmups runs (string-upcase (symbol-name audio)))
      (dotimes (index warmups)
        (run-trial (format nil "WARMUP-~D" (1+ index)) audio))
      (dotimes (index runs)
        (let ((result (run-trial (format nil "RUN-~D" (1+ index)) audio)))
          (push result results)
          (print-trial result)))
      (setf results (nreverse results))
      (format t "~&SUMMARY runs=~D median-wall-elapsed=~,6Fs median-wall-rate=~D/s median-measured-frame-rate=~D/s median-target-frame-rate=~D/s max-period-misses=~D/~D sound-active-ticks-min=~D max=~D within-schedule-runs=~D/~D within-frame-window-runs=~D/~D target-runs=~D/~D~%"
              runs
              (median-value (mapcar (lambda (r) (getf r :wall-elapsed)) results))
              (truncate (median-value
                         (mapcar (lambda (r) (getf r :wall-rate)) results)))
              (truncate (median-value
                         (mapcar (lambda (r) (getf r :measured-frame-rate)) results)))
              (truncate (median-value
                          (mapcar (lambda (r) (getf r :target-frame-rate)) results)))
              (reduce #'max results :key (lambda (r) (getf r :period-misses))
                      :initial-value 0)
              (getf (first results) :period-count)
              (reduce #'min results
                      :key (lambda (r) (getf r :sound-active-ticks))
                      :initial-value +bench-ticks+)
              (reduce #'max results
                      :key (lambda (r) (getf r :sound-active-ticks))
                      :initial-value 0)
              (count-if (lambda (r) (getf r :within-schedule)) results)
              runs
              (count-if (lambda (r) (getf r :within-frame-window)) results)
              runs
              (count-if (lambda (r) (getf r :target-met)) results)
              runs)
      (host-kit:quit 0)))

  (main))
