(in-package #:cl-chip8)

(defun quit-key-event-p (event)
  (and (eq (key-event-type event) :special)
       (member (key-event-code event) '(:escape :control-c))))

(defun %read-available-string (stream)
  (with-output-to-string (out)
    (loop for character = (read-char-no-hang stream nil nil)
          while character do (write-char character out))))

(defun %poll-input-events (decoder stream)
  (let ((input (%read-available-string stream)))
    (if (plusp (length input))
        (decode-input-chunk decoder input)
        (decode-input-chunk decoder "" :eof nil))))

(defun %instructions-per-tick (app)
  (multiple-value-bind (instructions remainder)
      (floor (+ (chip8-app-instruction-remainder app)
                (chip8-app-clock-hz app)) 60)
    (setf (chip8-app-instruction-remainder app) remainder)
    instructions))

(defun %mapped-key (event)
  (and (eq (key-event-type event) :character)
       (cdr (assoc (char-downcase (key-event-code event)) +keypad-mapping+))))

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
       (when (chip8-app-paused-p app)
         (setf (chip8-app-paused-p app) nil)
         (step-chip8-app! app :advance-timers-p nil)
         (setf (chip8-app-paused-p app) t)
         (setf (chip8-app-state-machine app)
               (step-chip8-control-state
                (chip8-app-state-machine app) :step)))
       t)
      ((eq special :backspace)
       (chip8-reset! (chip8-app-machine app))
       (setf (chip8-app-paused-p app) nil
             (chip8-app-state-machine app) (make-chip8-control-state-machine))
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

(defun %advance-chip8! (app)
  (%apply-key-events! app (%poll-input-events (chip8-app-decoder app) *standard-input*))
  (unless (chip8-app-quit-p app)
    (when (string= (chip8-control-state (chip8-app-state-machine app)) "ready")
      (setf (chip8-app-state-machine app)
            (step-chip8-control-state (chip8-app-state-machine app) :start)))
    (when (string= (chip8-control-state (chip8-app-state-machine app)) "waiting-display")
      (resume-chip8-app app (make-chip8-control-event :tick)))
    (unless (member (chip8-control-state (chip8-app-state-machine app))
                    '("paused" "waiting-key" "waiting-display" "finished" "error")
                    :test #'string=)
      (step-chip8-app! app)))
  app)

(defun %render-chip8-app! (app)
  (let ((screen (renderer-screen (chip8-app-renderer app)))
        (framebuffer (chip8-framebuffer-snapshot (chip8-app-machine app)))
        (sound-active-p (plusp (chip8-machine-sound-timer (chip8-app-machine app)))))
    (if (chip8-app-render-pipeline app)
        (render-chip8-concurrently! screen framebuffer (chip8-app-render-pipeline app)
                                    :sound-active-p sound-active-p)
        (render-chip8! screen framebuffer (chip8-app-render-state app)
                       :sound-active-p sound-active-p))
    (renderer-render (chip8-app-renderer app))))

(defun %chip8-app-finished-p (app)
  (or (chip8-app-quit-p app)
      (member (chip8-control-state (chip8-app-state-machine app))
              '("finished" "error") :test #'string=)))

(defun run (&key rom-path (clock-hz +default-clock-hz+)
                 (quirks (make-chip8-quirks)) (stream *standard-output*))
  (let ((machine (make-chip8-machine :quirks quirks)))
    (load-rom-file machine rom-path)
    (with-chip8-render-pipeline (pipeline)
      (let ((app (make-chip8-app
                  :machine machine :state-machine (make-chip8-control-state-machine)
                  :renderer (make-renderer +screen-width+ +screen-height+)
                  :render-state (make-chip8-render-state)
                  :render-pipeline pipeline
                  :decoder (make-input-decoder) :clock-hz clock-hz
                  :started-at (get-internal-real-time))))
        (with-raw-mode ()
          (with-terminal-session
              (session-stream :stream stream :hide-cursor t :alternate-screen t
                              :keyboard-enhancements 10)
            (tick-loop-run-realtime app #'%advance-chip8! #'%render-chip8-app!
                                     #'%chip8-app-finished-p
                                     :stream session-stream :interval 1/60)))
        app))))
