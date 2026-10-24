(in-package #:cl-chip8)

(defconstant +audio-frames-per-write+
  480)

(defstruct (chip8-audio-output (:constructor %make-chip8-audio-output))
  stream thread machine
  (writer (function cl-audio-kit:write-frames) :type function)
  (lock (sb-thread:make-mutex))
  (phase-reset-generation 0 :type integer)
  (frames-written 0 :type integer)
  (stopped-p nil :type boolean)
  (worker-condition nil :type (or null condition)))

(defun %audio-output-snapshot (output)
  (sb-thread:with-mutex ((chip8-audio-output-lock output))
    (values (chip8-audio-output-stopped-p output)
            (chip8-audio-output-phase-reset-generation output))))
(defun %synthesize-machine-audio-frames (machine frame-count bit-phase)
  (multiple-value-bind (platform sound-timer pattern pitch)
      (%chip8-machine-audio-snapshot machine)
    (if (eq platform :xo-chip)
        (synthesize-audio-frames frame-count sound-timer pattern pitch bit-phase)
        (synthesize-audio-frames frame-count
                                  sound-timer
                                  +default-audio-pattern+
                                  64
                                  bit-phase))))

(defun %record-audio-output-failure! (output condition)
  (sb-thread:with-mutex ((chip8-audio-output-lock output))
                        (setf (chip8-audio-output-worker-condition output) condition
                              (chip8-audio-output-stopped-p output) t)))

(defun %audio-output-worker (output)
  (let ((phase 0d0)
        (seen-generation 0))
    (handler-case
        (loop
          (multiple-value-bind (stopped-p generation)
              (%audio-output-snapshot output)
            (when stopped-p
              (return))
            (unless (= generation seen-generation)
              (setf phase 0d0
                    seen-generation generation))
            (multiple-value-bind (samples next-phase)
                (%synthesize-machine-audio-frames
                 (chip8-audio-output-machine output)
                 +audio-frames-per-write+
                 phase)
              (let ((written
                      (funcall (chip8-audio-output-writer output)
                               (chip8-audio-output-stream output)
                               samples)))
                (unless (= written +audio-frames-per-write+)
                  (error "Audio output wrote ~D of ~D frames."
                         written +audio-frames-per-write+))
                (setf phase next-phase)
                (sb-thread:with-mutex ((chip8-audio-output-lock output))
                  (incf (chip8-audio-output-frames-written output)
                        written))))))
      (error (condition)
        (%record-audio-output-failure! output condition)))))

(defun %open-chip8-audio-stream (&optional
                                 (open-stream #'cl-audio-kit:open-output-stream))
  (funcall open-stream
           :sample-rate
           +audio-sample-rate+
           :channels
           1
           :sample-format
           :float32))

(defun %resolve-chip8-audio-mode (mode &key
                                       (open-stream
                                        #'cl-audio-kit:open-output-stream)
                                       on-fallback)
  (ecase mode
    (:auto
     (handler-case (values :pcm (%open-chip8-audio-stream open-stream))
       (cl-audio-kit:audio-error (condition)
         (when on-fallback
           (funcall on-fallback condition))
         (values :bell nil))))
    (:pcm (values :pcm (%open-chip8-audio-stream open-stream)))
    (:bell (values :bell nil))
    (:off (values :off nil))))

(defun start-chip8-audio-output (stream machine &key
                                                (writer
                                                  (function cl-audio-kit:write-frames)))
  (declare (type chip8-machine machine)
           (type function writer))
  (let* ((output (%make-chip8-audio-output
                  :stream stream
                  :machine machine
                  :writer writer))
         (thread nil))
    (handler-case
        (setf thread (sb-thread:make-thread
                      (lambda () (%audio-output-worker output))
                      :name "cl-chip8-audio"))
      (error (condition)
        (cl-audio-kit:close-output-stream stream)
        (error condition)))
    (setf (chip8-audio-output-thread output) thread)
    output))

(defun %synchronize-chip8-audio-state! (app)
  (let* ((machine (chip8-app-machine app))
         (sound-timer (chip8-machine-sound-timer machine))
         (previous-timer (chip8-app-last-audio-sound-timer app))
         (output (chip8-app-audio-output app)))
    (when (and (eq (chip8-app-audio-mode app) :bell)
               (zerop previous-timer)
               (plusp sound-timer)
               (chip8-app-stream app))
      (let* ((now (get-internal-real-time))
             (last-bell (chip8-app-last-audio-bell-time app)))
        (when (or (null last-bell)
                  (>= (- now last-bell)
                      (/ internal-time-units-per-second 4)))
          (write-char (code-char 7) (chip8-app-stream app))
          (finish-output (chip8-app-stream app))
          (setf (chip8-app-last-audio-bell-time app) now))))
    (setf (chip8-app-last-audio-sound-timer app) sound-timer)
    (when output
      (let ((failure (chip8-audio-output-failure output)))
        (when failure
          (setf (chip8-app-error app) failure
                (chip8-app-quit-p app) t))))
    app))

(defun reset-chip8-audio-phase! (output)
  (sb-thread:with-mutex ((chip8-audio-output-lock output))
                        (incf
                         (chip8-audio-output-phase-reset-generation output)))
  output)

(defun chip8-audio-output-failure (output)
  (sb-thread:with-mutex ((chip8-audio-output-lock output))
                        (chip8-audio-output-worker-condition output)))

(defun chip8-audio-output-stats (output)
  (values
   (sb-thread:with-mutex ((chip8-audio-output-lock output))
                         (chip8-audio-output-frames-written output))
   (cl-audio-kit:stream-latency (chip8-audio-output-stream output))))

(defun stop-chip8-audio-output! (output)
  (sb-thread:with-mutex ((chip8-audio-output-lock output))
                        (setf (chip8-audio-output-stopped-p output) t))
  (sb-thread:join-thread (chip8-audio-output-thread output))
  (cl-audio-kit:close-output-stream (chip8-audio-output-stream output))
  output)
