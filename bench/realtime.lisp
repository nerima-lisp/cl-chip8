(require :asdf)
  (let* ((script-path *load-truename*)
         (root (truename
                (merge-pathnames #p"../"
                                 (uiop:pathname-directory-pathname script-path))))
         (bootstrap (merge-pathnames #p"tools/bootstrap.lisp" root)))
    (load bootstrap)
    (configure-local-source-registry root)
    (asdf:load-system "cl-chip8"))

  (defconstant +bench-clock-hz+ 60000)
  (defconstant +bench-interval+ (/ 1d0 60d0))

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

  (progn
  (defun minimum-pcm-block-count (run-start run-finish)
    "Require all expected PCM blocks except one, allowing a single missed 10 ms slot."
    (max 1
         (1- (floor (* (- run-finish run-start)
                       cl-chip8::+audio-sample-rate+)
                    cl-chip8::+audio-frames-per-write+))))
  (defparameter +pcm-interruption-gap-threshold+
    (/ (* 2d0 cl-chip8::+audio-frames-per-write+)
       cl-chip8::+audio-sample-rate+)
    "Two nominal PCM block intervals define one 20 ms interruption."))

(progn
  (defun bench-mode ()
    (let ((value (or (host-kit:getenv "CL_CHIP8_BENCH_MODE") "recording")))
      (cond ((string-equal value "advance") :advance)
            ((string-equal value "render") :render)
            ((string-equal value "tty") :tty)
            ((string-equal value "recording") :recording)
            ((string-equal value "hardware") :hardware)
            (t (error "Unsupported benchmark mode: ~A" value)))))

  (defun bench-integer-env (name default minimum)
    (let ((value (host-kit:getenv name)))
      (if (null value)
          default
          (let ((number (handler-case (parse-integer value)
                          (parse-error () nil))))
            (unless (and number (>= number minimum))
              (error "~A must be an integer >= ~D; got ~S."
                     name minimum value))
            number))))

  (defun bench-report-only-p ()
    (let ((value (host-kit:getenv "CL_CHIP8_BENCH_REPORT_ONLY")))
      (cond ((null value) t)
            ((string-equal value "0") nil)
            ((string-equal value "1") t)
            (t (error "Unsupported report-only value: ~A" value)))))

  (defun make-event-recorder ()
    (let* ((main-thread sb-thread:*current-thread*)
           (main-events (make-hash-table :test #'eq))
           (audio-thread nil)
           (audio-events nil))
      (values
       (lambda (event tick value)
         (let ((events
                 (cond ((eq sb-thread:*current-thread* main-thread)
                        main-events)
                       ((and audio-thread
                             (eq sb-thread:*current-thread* audio-thread))
                        audio-events)
                       (t
                        (error "Timing event came from an unregistered thread.")))))
           (push (cons tick value) (gethash event events))))
       (lambda (thread)
         (when audio-thread
           (error "An audio worker thread is already registered."))
         (setf audio-thread thread
               audio-events (make-hash-table :test #'eq))
         thread)
       (lambda ()
         (let ((copy (make-hash-table :test #'eq)))
           (dolist (events (list main-events audio-events))
             (when events
               (maphash
                (lambda (event samples)
                  (setf (gethash event copy)
                        (append (gethash event copy) (copy-list samples))))
                events)))
           copy)))))
  (defun event-values (events event)
    (mapcar #'cdr (gethash event events)))

  (defun percentile-value (values percentile)
    (let* ((sorted (sort (copy-list values) #'<))
           (position (* percentile (1- (length sorted))))
           (lower (floor position))
           (upper (ceiling position))
           (fraction (- position lower)))
      (+ (nth lower sorted)
         (* fraction (- (nth upper sorted) (nth lower sorted))))))

  (defun maximum (values)
    (reduce #'max values :initial-value 0d0))

  (defun total (values)
    (reduce #'+ values :initial-value 0d0))

  (defun print-phase-metric (event samples)
    (let ((values (mapcar (lambda (sample) (float (cdr sample) 1d0))
                          samples)))
      (format t "~&PHASE event=~A count=~D"
              (string-downcase (symbol-name event)) (length values))
      (if values
          (if (eq event :frame-drop)
              (format t " total=~D slots p50=~,3F slots p95=~,3F slots p99=~,3F slots max=~,3F slots"
                      (round (total values))
                      (percentile-value values 0.50d0)
                      (percentile-value values 0.95d0)
                      (percentile-value values 0.99d0)
                      (maximum values))
              (format t " total=~,6Fs p50=~,6Fs p95=~,6Fs p99=~,6Fs max=~,6Fs"
                      (total values)
                      (percentile-value values 0.50d0)
                      (percentile-value values 0.95d0)
                      (percentile-value values 0.99d0)
                      (maximum values)))
          (format t " total=0 p50=NA p95=NA p99=NA max=NA"))
      (terpri)))
  (defun command-output-or-unavailable (command)
    (handler-case
        (let* ((output (uiop:run-program command
                                        :output :string
                                        :error-output nil))
               (value
                 (string-trim '(#\Space #\Tab #\Newline #\Return) output)))
          (if (plusp (length value)) value "unavailable"))
      (error () "unavailable")))
  (defun nix-system-name ()
    (let ((os (string-downcase (software-type)))
          (arch (string-downcase (machine-type))))
      (cond ((search "darwin" os)
             (if (or (search "arm" arch) (search "aarch64" arch))
                 "aarch64-darwin"
                 "x86_64-darwin"))
            ((search "linux" os)
             (if (or (search "arm" arch) (search "aarch64" arch))
                 "aarch64-linux"
                 "x86_64-linux"))
            (t "unavailable"))))

  (defun print-environment ()
    (format t "~&ENV os=~A os-version=~A arch=~A nix-system=~A sbcl=~A pty-size=~A load-average=~A~%"
            (software-type)
            (command-output-or-unavailable '("sw_vers" "-productVersion"))
            (machine-type) (nix-system-name)
            (lisp-implementation-version)
            (command-output-or-unavailable '("sh" "-c" "stty size </dev/tty"))
            (command-output-or-unavailable '("sysctl" "-n" "vm.loadavg"))))
  (defun bench-gc-count ()
    (loop for generation from 0 below 7
          sum (sb-ext:generation-number-of-gcs generation)))
  (defun required-event-count (events event expected)
    (let ((actual (length (gethash event events))))
      (unless (= actual expected)
        (error "Missing benchmark measurement ~A: expected ~D, got ~D."
               event expected actual))))

  (defun print-event-report (events)
    (dolist (event '(:advance :render :write-string :finish-output
                     :deadline-sleep :wake-overshoot :deadline-miss
                     :frame-drop :display-lock-wait :display-lock-hold
                     :pcm-block-gap))
      (print-phase-metric event (gethash event events))))

  (progn
    (defun gap-interruption-times (measured-gaps run-start run-finish)
      "Count overlapping threshold-crossing gaps, clamping pre-run crossings to run start."
      (loop for sample in measured-gaps
            for next = (car sample)
            for gap = (cdr sample)
            for previous = (- next gap)
            for crossing = (+ previous +pcm-interruption-gap-threshold+)
            when (and (< previous run-finish)
                      (> next run-start)
                      (>= gap +pcm-interruption-gap-threshold+)
                      (<= crossing run-finish))
              collect (max 0 (- crossing run-start))))
    (defun sliding-interruption-limit-met-p (times)
      (loop for (left right) on times
            while right
            always (>= (- right left) 10d0))))

  (defun run-loop (app stream mode target-ticks record-event)
    (let* ((machine (cl-chip8::chip8-app-machine app))
           (instructions-before (cl-chip8:chip8-machine-instructions machine))
           (ticks 0) (render-calls 0) (actual-renders 0)
           (changed-frames 0) (frame-characters 0)
           (sound-active-ticks 0)
           (instruction-deltas '()) (tick-starts '()))
      (labels ((advance (state)
                 (let ((before (cl-chip8:chip8-machine-instructions machine)))
                   (incf ticks)
                   (push (monotonic-seconds) tick-starts)
                   (cl-chip8::%advance-chip8! state cl-chip8:+screen-width+ cl-chip8:+screen-height+)
                   (push (- (cl-chip8:chip8-machine-instructions machine)
                            before)
                         instruction-deltas))
                 (when (plusp (cl-chip8:chip8-machine-sound-timer machine))
                   (incf sound-active-ticks))
                 state)
               (render (state)
                 (incf render-calls)
                 (unless (eq mode :advance)
                   (incf actual-renders)
                   (let ((frame (cl-chip8::%render-chip8-app! state)))
                     (unless (stringp frame)
                       (error "Render returned a non-string frame: ~S" frame))
                     (when (plusp (length frame))
                       (incf changed-frames)
                       (incf frame-characters (length frame)))
                     frame)))
               (stop (state)
                 (declare (ignore state))
                 (>= ticks target-ticks)))
        (let* ((gc-count-before (bench-gc-count))
               (gc-time-before sb-ext:*gc-run-time*)
               (started (monotonic-seconds)))
          (progn
            (cl-tty-kit:tick-loop-run-realtime
             app #'advance #'render #'stop
             :stream stream :interval +bench-interval+
             :on-timing record-event)
            (let ((app-error (cl-chip8::chip8-app-error app)))
              (when app-error
                (error app-error))))
          (let* ((finished (monotonic-seconds))
                 (gc-count-after (bench-gc-count))
                 (gc-time-after sb-ext:*gc-run-time*)
                 (gc-count (- gc-count-after gc-count-before))
                 (gc-time (/ (- gc-time-after gc-time-before)
                             internal-time-units-per-second))
                 (wall-elapsed (- finished started))
                 (instructions (- (cl-chip8:chip8-machine-instructions machine)
                                  instructions-before))
                 (starts (nreverse tick-starts))
                 (frame-window
                   (+ (- (car (last starts)) (first starts))
                      +bench-interval+))
                 (tick-rate (/ ticks frame-window))
                 (instruction-deltas (nreverse instruction-deltas))
                 (expected-per-frame (round (/ +bench-clock-hz+ 60))))
            (unless (= ticks target-ticks)
              (error "Invalid tick work: expected ~D ticks, got ~D."
                     target-ticks ticks))
            (unless (and (= (length instruction-deltas) target-ticks)
                         (every (lambda (count)
                                  (= count expected-per-frame))
                                instruction-deltas)
                         (= instructions (* target-ticks expected-per-frame)))
              (error "Invalid frame work: instruction deltas are not uniformly ~D."
                     expected-per-frame))
            (unless (if (eq mode :advance)
                        (zerop actual-renders)
                        (and (= actual-renders target-ticks)
                             (plusp changed-frames)))
              (error "Selected render workload did not execute: mode=~A renders=~D frames=~D."
                     mode actual-renders changed-frames))
            (list :ticks ticks
                  :render-calls render-calls
                  :actual-renders actual-renders
                  :changed-frames changed-frames
                  :frame-characters frame-characters
                  :instructions instructions
                  :instructions-per-frame expected-per-frame
                  :instruction-deltas instruction-deltas
                  :run-start started
                  :run-finish finished
                  :wall-elapsed wall-elapsed
                  :wall-rate (/ instructions wall-elapsed)
                  :frame-window frame-window
                  :tick-rate tick-rate
                  :gc-count gc-count
                  :gc-time gc-time
                  :sound-active-ticks sound-active-ticks
                  :sound-timer
                  (cl-chip8:chip8-machine-sound-timer machine)))))))
  (defun run-output (app mode target-ticks record-event)
    (if (member mode '(:advance :render))
        (let ((stream (make-broadcast-stream)))
          (values (run-loop app stream mode target-ticks record-event)
                  :discard nil))
        (progn
          (unless (and (interactive-stream-p *standard-input*)
                       (interactive-stream-p *standard-output*))
            (error "Mode ~A requires a PTY; use script with a configured size."
                   mode))
          (let ((result nil))
            (cl-tty-kit:with-terminal-session
                (stream :stream *standard-output* :fd 0 :raw-mode t
                        :alternate-screen t :hide-cursor t)
              (setf (cl-chip8::chip8-app-stream app) stream)
              (setf result
                    (run-loop app stream mode target-ticks record-event)))
            (values result :tty nil)))))

  (defun make-trial-audio-writer (record-only record-pcm-completion)
    (let ((deadline nil))
      (lambda (stream samples)
        (unless (= (length samples) cl-chip8::+audio-frames-per-write+)
          (error "Invalid PCM block size: ~D." (length samples)))
        (let ((written (cl-audio-kit:write-frames stream samples)))
          (unless (= written cl-chip8::+audio-frames-per-write+)
            (error "Incomplete PCM block write: ~D of ~D."
                   written cl-chip8::+audio-frames-per-write+))
          (funcall record-pcm-completion (monotonic-seconds) samples)
          (when record-only
            (setf deadline
                  (+ (or deadline (monotonic-seconds))
                     (/ written cl-chip8::+audio-sample-rate+)))
            (loop for remaining = (- deadline (monotonic-seconds))
                  while (plusp remaining)
                  do (sleep remaining)))
          written))))

  (defun make-trial-audio-output (audio-stream record-only
                                  record-pcm-completion
                                  register-audio-thread app)
    (let ((audio-output
            (cl-chip8::start-chip8-audio-output
             audio-stream
             (cl-chip8::chip8-app-machine app)
             :writer
             (make-trial-audio-writer record-only
                                      record-pcm-completion))))
      (funcall register-audio-thread
               (cl-chip8::chip8-audio-output-thread audio-output))
      audio-output))

    (defun install-trial-lock-timing-hook (record-event lock-mode)
      (let ((prior-hook cl-chip8::*display-audio-lock-timing-hook*))
        (ecase lock-mode
          (:off
           (setf cl-chip8::*display-audio-lock-timing-hook* nil)
           (values prior-hook nil))
          (:count
           (setf cl-chip8::*display-audio-lock-acquisition-count* 0
                 cl-chip8::*display-audio-lock-timing-hook* :count-only)
           (values prior-hook nil))
          (:timing
           (let ((active-p t))
             (setf cl-chip8::*display-audio-lock-timing-hook*
                   (lambda (kind value)
                     (when active-p
                       (funcall record-event
                                (ecase kind
                                  (:wait :display-lock-wait)
                                  (:hold :display-lock-hold))
                                0 value))))
             (values prior-hook (lambda () (setf active-p nil))))))))

  (defun restore-trial-lock-timing-hook (prior-hook deactivate-hook)
    (when deactivate-hook
      (funcall deactivate-hook))
    (setf cl-chip8::*display-audio-lock-timing-hook* prior-hook))

  (defun aggregate-trial-pcm (pcm-completions pcm-nonzero-completions
                              run-start run-finish record-event)
    (let* ((measured-gaps
             (loop for previous in pcm-completions
                   for next in (cdr pcm-completions)
                   for gap = (- next previous)
                   when (and (< previous run-finish) (> next run-start))
                     collect (cons next gap)))
           (pcm-gaps (mapcar #'cdr measured-gaps))
           (measured-pcm-blocks
             (count-if (lambda (time)
                         (and (>= time run-start) (<= time run-finish)))
                       pcm-completions))
           (measured-nonzero-blocks
             (count-if (lambda (time)
                         (and (>= time run-start) (<= time run-finish)))
                       pcm-nonzero-completions))
           (interruption-times
             (gap-interruption-times measured-gaps run-start run-finish)))
      (dolist (gap pcm-gaps)
        (funcall record-event :pcm-block-gap 0 gap))
      (values pcm-gaps interruption-times measured-pcm-blocks
              measured-nonzero-blocks)))

  (defun trial-target-met-p (mode result seconds misses dropped-slots
                             measured-pcm-blocks run-start run-finish
                             interruption-times)
    (and (member mode '(:recording :hardware))
         (>= (getf result :tick-rate) 60d0)
         (>= (getf result :wall-rate) 60000d0)
         (>= (getf result :wall-elapsed) seconds)
         (zerop misses)
         (and (zerop dropped-slots)
              (>= measured-pcm-blocks
                  (minimum-pcm-block-count run-start run-finish)))
         (sliding-interruption-limit-met-p
          (sort (copy-list interruption-times) #'<))))

  (defun run-trial (label mode seconds lock-mode)
    (let ((trial-start (monotonic-seconds))
          (trial nil))
      (unless (plusp (length (make-bench-rom)))
        (error "Selected benchmark ROM is empty."))
      (cl-chip8:with-chip8-render-pipeline (pipeline)
        (let* ((app (make-bench-app pipeline))
               ;; Tick one is immediate; the extra slot keeps the run above its duration floor.
               (ticks (+ 2 (* seconds 60)))
               (record-event nil) (register-audio-thread nil)
               (snapshot-events nil)
               (audio-stream nil) (recording-device nil) (audio-output nil)
               (audio-mode (if (member mode '(:recording :hardware))
                               :pcm :off))
               (recorded-chunks nil) (recorded-blocks 0) (recorded-frames 0)
               (recorded-nonzero-samples 0)
               (pcm-completions '()) (pcm-nonzero-completions '())
               (pcm-gaps '()) (interruption-times '())
               (measured-pcm-blocks 0) (measured-nonzero-blocks 0)
               (pcm-frames 0) (nonzero-pcm-samples 0)
               (audio-worker-failure nil) (result nil) (sink nil) (captured nil)
               (record-only (eq mode :recording))
               (backend (if record-only "recording-device"
                            (if (eq mode :hardware) "default-output" "none")))
               (prior-lock-hook cl-chip8::*display-audio-lock-timing-hook*)
               (deactivate-lock-hook nil))
          (multiple-value-bind (new-recorder new-register-thread event-snapshot)
              (make-event-recorder)
            (setf record-event new-recorder
                  register-audio-thread new-register-thread
                  snapshot-events event-snapshot))
          (unwind-protect
               (progn
                 (setf (cl-chip8::chip8-app-audio-mode app) audio-mode)
                 (when record-only
                   (setf recording-device
                         (cl-audio-kit:make-recording-device)))
                 (when (member mode '(:recording :hardware))
                   (setf audio-stream
                         (if recording-device
                             (cl-audio-kit:open-output-stream
                              :sample-rate cl-chip8::+audio-sample-rate+
                              :channels 1 :sample-format :float32
                              :device recording-device)
                             (cl-audio-kit:open-output-stream
                              :sample-rate cl-chip8::+audio-sample-rate+
                              :channels 1 :sample-format :float32)))
                   (setf audio-output
                         (make-trial-audio-output
                          audio-stream record-only
                          (lambda (completed-at samples)
                            (let ((nonzero
                                    (count-if
                                     (lambda (sample)
                                       (not (zerop sample)))
                                     samples)))
                              (incf nonzero-pcm-samples nonzero)
                              (push completed-at pcm-completions)
                              (when (plusp nonzero)
                                (push completed-at
                                      pcm-nonzero-completions))))
                          register-audio-thread app))
                   (setf audio-stream nil
                         (cl-chip8::chip8-app-audio-output app) audio-output))
                 (multiple-value-setq (prior-lock-hook deactivate-lock-hook)
                   (install-trial-lock-timing-hook record-event lock-mode))
                 (progn
                  (format t "~&TRIAL-LOAD label=~A phase=before value=~A~%"
                          label
                          (command-output-or-unavailable
                           (list "sysctl" "-n" "vm.loadavg")))
                  (finish-output)
                  (unwind-protect
                      (multiple-value-setq (result sink captured)
                        (run-output app mode ticks record-event))
                    (restore-trial-lock-timing-hook
                     prior-lock-hook deactivate-lock-hook)
                    (format t "~&TRIAL-LOAD label=~A phase=after value=~A~%"
                            label
                            (command-output-or-unavailable
                             (list "sysctl" "-n" "vm.loadavg")))
                    (finish-output)))
                 (when audio-output
                   (cl-chip8::stop-chip8-audio-output! audio-output)
                   (setf pcm-frames
                         (sb-thread:with-mutex
                             ((cl-chip8::chip8-audio-output-lock audio-output))
                           (cl-chip8::chip8-audio-output-frames-written
                            audio-output))
                         audio-worker-failure
                         (cl-chip8::chip8-audio-output-failure audio-output)
                         audio-output nil))
                 (when recording-device
                   (setf recorded-chunks
                         (cl-audio-kit:recorded-samples recording-device)
                         recorded-blocks (length recorded-chunks)
                         recorded-frames
                         (reduce #'+ recorded-chunks :key #'length
                                 :initial-value 0)
                         recorded-nonzero-samples
                         (loop for samples in recorded-chunks
                               sum (count-if
                                    (lambda (sample) (not (zerop sample)))
                                    samples)))
                   (unless (every
                            (lambda (samples)
                              (= (length samples)
                                 cl-chip8::+audio-frames-per-write+))
                            recorded-chunks)
                     (error "Recording backend returned an invalid PCM block.")))
                 (when (and recording-device
                            (/= recorded-frames
                                (* recorded-blocks
                                   cl-chip8::+audio-frames-per-write+)))
                   (error "Recording frame count does not match its PCM blocks."))
                 (setf pcm-completions (nreverse pcm-completions)
                       pcm-nonzero-completions
                       (nreverse pcm-nonzero-completions))
                 (let* ((run-start (getf result :run-start))
                        (run-finish (getf result :run-finish)))
                   (multiple-value-setq
                       (pcm-gaps interruption-times measured-pcm-blocks
                        measured-nonzero-blocks)
                     (aggregate-trial-pcm pcm-completions
                                          pcm-nonzero-completions
                                          run-start run-finish record-event))
                   (setf snapshot-events (funcall snapshot-events))
                   (required-event-count snapshot-events :advance ticks)
                   (required-event-count snapshot-events :render ticks)
                   (required-event-count snapshot-events :deadline-sleep ticks)
                   (required-event-count snapshot-events :wake-overshoot ticks)
                   (when (eq lock-mode :timing)
                     (unless (and (plusp (length (gethash :display-lock-wait snapshot-events)))
                                  (plusp (length (gethash :display-lock-hold snapshot-events))))
                       (error "Display/audio lock timing measurements are missing.")))
                   (when (member mode '(:render :tty :recording :hardware))
                     (required-event-count snapshot-events :write-string
                                           (getf result :changed-frames))
                     (required-event-count snapshot-events :finish-output
                                           (getf result :changed-frames)))
                   (unless (null audio-worker-failure)
                     (error "Audio worker failed: ~A" audio-worker-failure))
                   (when (member mode '(:recording :hardware))
                     (unless (and (plusp pcm-frames)
                                  (plusp measured-nonzero-blocks)
                                  (>= measured-pcm-blocks
                                      (minimum-pcm-block-count run-start run-finish)))
                       (error "Selected audio workload produced too few PCM blocks."))
                     (when record-only
                       (unless (and (plusp recorded-blocks)
                                    (plusp recorded-frames)
                                    (plusp recorded-nonzero-samples))
                         (error "Recording backend produced no valid nonzero PCM.")))
                     (required-event-count snapshot-events :pcm-block-gap
                                           (length pcm-gaps)))
                   (let* ((misses
                            (length (gethash :deadline-miss snapshot-events)))
                          (dropped-slots
                            (reduce #'+
                                    (event-values snapshot-events :frame-drop)
                                    :initial-value 0))
                          (target-met
                            (trial-target-met-p
                             mode result seconds misses dropped-slots
                             measured-pcm-blocks run-start run-finish
                             interruption-times)))
                     (setf trial
                           (list :label label :mode mode :lock-mode lock-mode
                                 :lock-count (when (eq lock-mode :count)
                                               cl-chip8::*display-audio-lock-acquisition-count*)
                                 :seconds seconds :ticks ticks :result result :sink sink
                                 :captured captured :backend backend :pcm-frames pcm-frames
                                 :pcm-blocks measured-pcm-blocks :pcm-gaps pcm-gaps
                                 :audio-nonzero-blocks measured-nonzero-blocks
                                 :audio-interruptions (length interruption-times)
                                 :underflow "UNAVAILABLE" :recorded-blocks recorded-blocks
                                 :recorded-frames recorded-frames
                                 :nonzero-pcm-samples nonzero-pcm-samples
                                 :recorded-nonzero-samples recorded-nonzero-samples
                                 :audio-worker-failure audio-worker-failure :trial-total nil
                                 :gc-count (getf result :gc-count) :gc-time (getf result :gc-time)
                                 :events snapshot-events :misses misses :dropped-slots dropped-slots
                                 :target-met target-met :queue-metrics "NOT-PRESENT"))))
             (unwind-protect
                  (when audio-output
                    (cl-chip8::stop-chip8-audio-output! audio-output))
               (unwind-protect
                    (when audio-stream
                      (cl-audio-kit:close-output-stream audio-stream))
                 (restore-trial-lock-timing-hook
                  prior-lock-hook deactivate-lock-hook)))))))
      (setf (getf trial :trial-total) (- (monotonic-seconds) trial-start))
      trial))
  (defun print-trial (trial)
    (let ((result (getf trial :result)))
      (format t "~&TRIAL label=~A mode=~A ticks=~D instructions=~D instruction-per-frame=~D render-calls=~D rendered-frames=~D changed-frames=~D tick-rate=~,3F/s wall-rate=~,3F instructions/s measured-run=~,6Fs trial-total=~,6Fs gc-count=~D gc-time=~,6Fs missed-deadlines=~D dropped-slots=~D pcm-blocks-measured/required=~A pcm-frames=~D pcm-gaps=~D audio-nonzero-blocks=~D audio-interruptions=~D backend=~A backend-underflow=~A recorded-blocks=~D recorded-frames=~D recorded-nonzero-samples=~D queue-metrics=~A target=~A~%"
              (getf trial :label) (string-upcase (symbol-name (getf trial :mode)))
              (getf result :ticks) (getf result :instructions)
              (getf result :instructions-per-frame)
              (getf result :render-calls) (getf result :actual-renders)
              (getf result :changed-frames) (getf result :tick-rate)
              (getf result :wall-rate) (getf result :wall-elapsed)
              (getf trial :trial-total) (getf trial :gc-count)
              (getf trial :gc-time) (getf trial :misses)
              (getf trial :dropped-slots) (format nil "~D/~A"
                                                  (getf trial :pcm-blocks)
                                                  (if (member (getf trial :mode)
                                                              (quote (:recording :hardware)))
                                                      (minimum-pcm-block-count
                                                       0 (getf result :wall-elapsed))
                                                    "NA"))
              (getf trial :pcm-frames) (length (getf trial :pcm-gaps))
              (getf trial :audio-nonzero-blocks)
              (getf trial :audio-interruptions) (getf trial :backend)
              (getf trial :underflow) (getf trial :recorded-blocks)
              (getf trial :recorded-frames)
              (getf trial :recorded-nonzero-samples)
              (getf trial :queue-metrics)
              (cond ((getf trial :target-met) "MET")
                    ((bench-report-only-p) "REPORT-ONLY")
                    (t "NOT-MET")))
      (print-event-report (getf trial :events))
      (progn
        (format t "~&PCM gaps p50=~A p95=~A p99=~A max=~A~%"
                (if (getf trial :pcm-gaps)
                    (percentile-value (getf trial :pcm-gaps) 0.50d0) "NA")
                (if (getf trial :pcm-gaps)
                    (percentile-value (getf trial :pcm-gaps) 0.95d0) "NA")
                (if (getf trial :pcm-gaps)
                    (percentile-value (getf trial :pcm-gaps) 0.99d0) "NA")
                (if (getf trial :pcm-gaps)
                    (maximum (getf trial :pcm-gaps)) "NA"))
        (when (numberp (getf trial :lock-count))
          (let ((count (getf trial :lock-count))
                (ticks (getf result :ticks)))
            (format t "~&LOCK-COUNT mode=~A total=~D ticks=~D per-tick=~,3F~%"
                    (string-upcase (symbol-name (getf trial :lock-mode)))
                    count ticks (/ count ticks)))))))
  (defun main ()
    (let* ((mode (bench-mode))
           (lock-mode
            (let ((value (string-downcase
                          (or (host-kit:getenv "CL_CHIP8_BENCH_LOCK_MODE")
                              "timing"))))
              (cond ((string= value "off") :off)
                    ((string= value "timing") :timing)
                    ((string= value "count") :count)
                    (t (error "Unsupported lock hook mode: ~A" value)))))
           (seconds (bench-integer-env "CL_CHIP8_BENCH_SECONDS" 10 10))
           (runs (bench-integer-env "CL_CHIP8_BENCH_RUNS" 3 2))
           (warmups (bench-integer-env "CL_CHIP8_BENCH_WARMUP" 1 0))
           (report-only (bench-report-only-p))
           (results '()))
      (when (or (and (not report-only)
                     (not (member mode '(:recording :hardware))))
                (and (eq lock-mode :count)
                     (not (eq mode :advance))))
        (error "Qualification requires recording or hardware mode; count mode requires advance mode."))
      (format t "~&P5 FR-014 mode=~A lock-hook=~A seconds=~D runs=~D warmups=~D report-only=~A sample-rate=~D block-frames=~D block-interval=~,3Fms interruption-gap>=~,3Fms interruption-window=gap-overlap-and-crossing-before-end timestamp=clamped-at-start basis=2*~D/~D s one-missed-block-allowance=1-block~%"
              (string-upcase (symbol-name mode))
              (string-upcase (symbol-name lock-mode))
              seconds runs warmups
              (if report-only "YES" "NO")
              cl-chip8::+audio-sample-rate+
              cl-chip8::+audio-frames-per-write+
              (* 1000d0
                 (/ cl-chip8::+audio-frames-per-write+
                    cl-chip8::+audio-sample-rate+))
              (* 1000d0 +pcm-interruption-gap-threshold+)
              cl-chip8::+audio-frames-per-write+
              cl-chip8::+audio-sample-rate+)
      (print-environment)
      (dotimes (index warmups)
        (run-trial (format nil "WARMUP-~D" (1+ index)) mode seconds lock-mode))
      (dotimes (index runs)
        (let ((trial (run-trial (format nil "RUN-~D" (1+ index)) mode seconds lock-mode)))
          (push trial results)
          (print-trial trial)))
      (setf results (nreverse results))
      (let ((misses (reduce #'+ results :key (lambda (trial)
                                               (getf trial :misses))
                            :initial-value 0))
            (drops (reduce #'+ results :key (lambda (trial)
                                              (getf trial :dropped-slots))
                           :initial-value 0))
            (interruptions (reduce #'+ results
                                   :key (lambda (trial)
                                          (getf trial :audio-interruptions))
                                   :initial-value 0))
            (target-met (every (lambda (trial) (getf trial :target-met))
                               results)))
        (format t "~&SUMMARY runs=~D mode=~A report-only=~A total-missed-deadlines=~D total-dropped-slots=~D total-audio-interruptions=~D target=~A~%"
                runs (string-upcase (symbol-name mode))
                (if report-only "YES" "NO") misses drops interruptions
                (if target-met "MET" "NOT-MET"))
        (finish-output)
        (host-kit:quit
         (if (or report-only (and target-met (zerop misses) (zerop drops)))
             0 1)))))

  (main))
