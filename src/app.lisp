(in-package #:cl-chip8)

(defun quit-key-event-p (event)
  (and (eq (key-event-type event) :special)
       (member (key-event-code event) '(:escape :control-c))))

(defun %read-available-string (stream)
  (with-output-to-string (out)
    (loop for character = (read-char-no-hang stream nil nil)
          while character do (write-char character out))))

(defun %poll-input-events (app stream)
  (let* ((decoder (chip8-app-decoder app))
         (input (%read-available-string stream))
         (now (funcall (chip8-app-input-clock app))))
    (if (plusp (length input))
        (progn
          (setf (chip8-app-last-input-time app) now)
          (decode-input-chunk decoder input))
        (let ((events (decode-input-chunk decoder "" :eof nil))
              (last-input-time (chip8-app-last-input-time app)))
          (if (and last-input-time
                   (>= (- now last-input-time)
                       (ceiling internal-time-units-per-second 10)))
              (progn
                (setf (chip8-app-last-input-time app) nil)
                (append events (cl-tty-kit:flush-input-decoder decoder)))
              events)))))

(defun %instructions-per-tick (app)
  (multiple-value-bind (instructions remainder)
      (floor (+ (chip8-app-instruction-remainder app)
                (chip8-app-clock-hz app)) 60)
    (setf (chip8-app-instruction-remainder app) remainder)
    instructions))

(defun %mapped-key (event)
  (and (eq (key-event-type event) :character)
       (cdr (assoc (char-downcase (key-event-code event)) +keypad-mapping+))))
(defun %chip8-app-render-mode (app mode)
  (if (and (eq mode :lores)
           (eq (chip8-platform-name
                (chip8-machine-platform (chip8-app-machine app)))
               :xo-chip))
      :half-block
      mode))

(defun %apply-control-key! (app event)
  (let ((character (and (eq (key-event-type event) :character)
                        (char-downcase (key-event-code event))))
        (special (and (eq (key-event-type event) :special)
                      (key-event-code event))))
    (cond
      ((and character (char= character #\p))
       (cond
         ((chip8-app-paused-p app)
          (setf (chip8-app-state-machine app)
                (step-chip8-control-state
                 (chip8-app-state-machine app) :resume))
          (setf (chip8-app-paused-p app) nil))
         ((string= (chip8-control-state (chip8-app-state-machine app))
                   "running")
          (setf (chip8-app-state-machine app)
                (step-chip8-control-state
                 (chip8-app-state-machine app) :pause))
          (setf (chip8-app-paused-p app) t)))
       t)
      ((and character (char= character #\o))
       (when (chip8-app-paused-p app)
         (setf (chip8-app-paused-p app) nil)
         (setf (chip8-app-state-machine app)
               (step-chip8-control-state
                (chip8-app-state-machine app) :resume)))
       t)
      ((and character (char= character #\n))
       (when (and (chip8-app-paused-p app)
                  (not (chip8-app-display-too-small-p app)))
         (setf (chip8-app-paused-p app) nil)
         (step-chip8-app! app :advance-timers-p nil)
         (setf (chip8-app-paused-p app) t)
         (setf (chip8-app-state-machine app)
               (step-chip8-control-state
                (chip8-app-state-machine app) :step)))
       t)
      ((eq special :backspace)
       (chip8-reset! (chip8-app-machine app))
       (when (chip8-app-audio-output app)
         (reset-chip8-audio-phase! (chip8-app-audio-output app)))
       (setf (chip8-app-last-audio-sound-timer app) 0
             (chip8-app-paused-p app) nil
             (chip8-app-state-machine app)
             (make-chip8-control-state-machine))
       t)
      (t nil))))

(defun %apply-key-event! (app event)
  (cond
    ((quit-key-event-p event)
     (setf (chip8-app-quit-p app) t)
     (setf (chip8-app-state-machine app)
           (step-chip8-control-state (chip8-app-state-machine app) :quit)))
    ((%apply-control-key! app event) app)
    ((%mapped-key event)
     (let ((key (%mapped-key event)))
       (if (eq (key-event-kind event) :release)
           (progn
             (chip8-key-up! (chip8-app-machine app) key)
             (when (string= (chip8-control-state (chip8-app-state-machine app)) "waiting-key")
               (resume-chip8-app app (make-chip8-control-event :key-release key))))
           (progn
             (chip8-key-down! (chip8-app-machine app) key)
             (when (string= (chip8-control-state (chip8-app-state-machine app)) "waiting-key")
               (resume-chip8-app app (make-chip8-control-event :key-press key))))))))
  app)

(defun %apply-key-events! (app events)
  (dolist (event events app) (%apply-key-event! app event)))

(defun %refresh-chip8-display! (app columns rows)
  (multiple-value-bind (mode required-columns required-rows)
      (%select-chip8-display-mode
       (chip8-machine-resolution (chip8-app-machine app))
       columns rows)
    (let* ((too-small-p (eq mode :too-small))
           (screen-columns
             (if too-small-p (max 1 columns) required-columns))
           (screen-rows
             (if too-small-p (max 1 rows) required-rows))
           (changed-p
             (or (not (eq mode (chip8-app-display-mode app)))
                 (/= screen-columns (chip8-app-display-columns app))
                 (/= screen-rows (chip8-app-display-rows app))))
           (render-mode (if too-small-p :lores (%chip8-app-render-mode app mode))))
      (setf (chip8-app-display-too-small-p app) too-small-p)
      (when changed-p
        (setf (chip8-app-display-mode app) mode
              (chip8-app-display-columns app) screen-columns
              (chip8-app-display-rows app) screen-rows)
        (when (chip8-app-render-state app)
          (let ((state (chip8-app-render-state app)))
            (setf (chip8-render-state-framebuffer state) nil
                  (chip8-render-state-sound-active-p state) nil
                  (chip8-render-state-display-mode state) render-mode)))
        (when (chip8-app-render-pipeline app)
          (let ((state
                  (chip8-render-pipeline-state
                   (chip8-app-render-pipeline app))))
            (setf (chip8-render-state-framebuffer state) nil
                  (chip8-render-state-sound-active-p state) nil
                  (chip8-render-state-display-mode state) render-mode)))
        (when (chip8-app-renderer app)
          (cl-tty-kit:renderer-resize
           (chip8-app-renderer app) screen-columns screen-rows)
          (cl-tty-kit:renderer-clear (chip8-app-renderer app))))
      (when (and too-small-p (chip8-app-renderer app))
        (let* ((screen (renderer-screen (chip8-app-renderer app)))
               (message
                 (format nil "Terminal too small. Need ~Dx~D."
                         required-columns required-rows))
               (visible-message
                 (subseq message 0 (min screen-columns (length message)))))
          (screen-write-string screen 0 0 visible-message)))
      (values mode required-columns required-rows))))

(defun %advance-chip8!
    (app &optional (columns nil columns-supplied-p)
               (rows nil rows-supplied-p))
  (flet ((refresh-display ()
           (when (chip8-app-renderer app)
             (if (and columns-supplied-p rows-supplied-p)
                 (%refresh-chip8-display! app columns rows)
                 (multiple-value-bind (terminal-columns terminal-rows)
                     (cl-tty-kit:terminal-size)
                   (%refresh-chip8-display!
                    app (or terminal-columns 0) (or terminal-rows 0)))))))
    (refresh-display)
    (let ((resolution (chip8-machine-resolution (chip8-app-machine app))))
      (%apply-key-events! app (%poll-input-events app *standard-input*))
      (unless (eq resolution
                  (chip8-machine-resolution (chip8-app-machine app)))
        (refresh-display)))
    (unless (chip8-app-quit-p app)
      (unless (chip8-app-display-too-small-p app)
        (when (string= (chip8-control-state (chip8-app-state-machine app))
                       "ready")
          (setf (chip8-app-state-machine app)
                (step-chip8-control-state
                 (chip8-app-state-machine app) :start)))
        (when (string= (chip8-control-state (chip8-app-state-machine app))
                       "waiting-display")
          (resume-chip8-app app (make-chip8-control-event :tick)))
        (unless (or (chip8-app-paused-p app)
                    (member (chip8-control-state
                             (chip8-app-state-machine app))
                            '("paused" "waiting-key" "waiting-display"
                              "finished" "error")
                            :test #'string=))
          (let ((resolution
                  (chip8-machine-resolution (chip8-app-machine app))))
            (step-chip8-app! app)
            (unless (eq resolution
                        (chip8-machine-resolution (chip8-app-machine app)))
              (refresh-display))))))
    (%synchronize-chip8-audio-state! app)
    app))

(defun %render-chip8-app! (app)
  (let ((screen (renderer-screen (chip8-app-renderer app)))
        (framebuffer (chip8-framebuffer-snapshot (chip8-app-machine app)))
        (mode (%chip8-app-render-mode app (chip8-app-display-mode app)))
        (sound-active-p
          (plusp (chip8-machine-sound-timer (chip8-app-machine app)))))
    (unless (chip8-app-display-too-small-p app)
      (if (chip8-app-render-pipeline app)
          (render-chip8-concurrently!
           screen framebuffer (chip8-app-render-pipeline app)
           :mode mode :sound-active-p sound-active-p)
          (render-chip8! screen framebuffer (chip8-app-render-state app)
                         :mode mode :sound-active-p sound-active-p)))
    (renderer-render (chip8-app-renderer app))))
(defun %chip8-app-finished-p (app)
  (or (chip8-app-quit-p app)
      (member (chip8-control-state (chip8-app-state-machine app))
              '("finished" "error") :test #'string=)))

(defun run (&key rom-path (rom-bytes nil rom-bytes-p) (clock-hz +default-clock-hz+) (platform :modern)
                 (quirks nil quirks-p) (stream *standard-output*)
                 (audio-mode :off) on-audio-fallback)
  (let ((machine (if quirks-p
                     (make-chip8-machine :platform platform :quirks quirks)
                     (make-chip8-machine :platform platform))))
    (if rom-bytes-p
        (load-rom machine rom-bytes)
        (load-rom-file machine rom-path))
    (with-chip8-render-pipeline (pipeline)
      (let* ((app (make-chip8-app
                   :machine machine
                   :state-machine (make-chip8-control-state-machine)
                   :renderer (make-renderer +screen-width+ +screen-height+)
                   :render-state (make-chip8-render-state)
                   :render-pipeline pipeline
                   :decoder (make-input-decoder)
                   :clock-hz clock-hz
                   :audio-mode audio-mode
                   :started-at (get-internal-real-time)))
             (audio-output nil)
             (audio-stream nil)
             (resolved-audio-mode :off))
        (unwind-protect
             (progn
               (multiple-value-setq (resolved-audio-mode audio-stream)
                 (%resolve-chip8-audio-mode
                  audio-mode
                  :on-fallback
                  (or on-audio-fallback
                      (lambda (condition)
                        (format *error-output*
                                "~&cl-chip8: audio output unavailable (~A); using terminal bell.~%"
                                condition)))))
               (setf (chip8-app-audio-mode app) resolved-audio-mode)
               (when (eq resolved-audio-mode :pcm)
                 (setf audio-output
                       (start-chip8-audio-output audio-stream machine)
                       audio-stream nil))
               (setf (chip8-app-audio-output app) audio-output)
               (with-raw-mode ()
                 (with-terminal-session
                     (session-stream :stream stream :hide-cursor t
                                     :alternate-screen t
                                     :keyboard-enhancements 10)
                   (setf (chip8-app-stream app) session-stream)
                   (multiple-value-bind (columns rows)
                       (cl-tty-kit:terminal-size)
                     (%refresh-chip8-display!
                      app (or columns 0) (or rows 0)))
                   (%synchronize-chip8-audio-state! app)
                   (tick-loop-run-realtime app
                                           #'%advance-chip8!
                                           #'%render-chip8-app!
                                           #'%chip8-app-finished-p
                                           :stream session-stream
                                           :interval 1/60))))
          (%cleanup-chip8-audio-resources! audio-output audio-stream))
        app))))
