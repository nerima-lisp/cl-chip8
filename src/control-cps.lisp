(in-package #:cl-chip8)

(defun resume-chip8-app (app event)
  (let ((machine (chip8-app-machine app))
        (type (and (chip8-control-event-p event)
                   (chip8-control-event-type event)))
        (key (and (chip8-control-event-p event)
                  (chip8-control-event-value event))))
    (let ((wait-kind (chip8-wait-state-kind (chip8-machine-waiting machine))))
      (case type
        (:tick (when (chip8-wait-state-kind (chip8-machine-waiting machine))
                 (chip8-resume! machine :tick)))
        (:key-press (when (chip8-wait-state-kind (chip8-machine-waiting machine))
                      (chip8-resume! machine (list :key-down key))))
        (:key-release (when (chip8-wait-state-kind (chip8-machine-waiting machine))
                        (chip8-resume! machine (list :key-up key)))))
        (when (and wait-kind (null (chip8-wait-state-kind (chip8-machine-waiting machine))))
          (setf (chip8-app-state-machine app)
                (step-chip8-control-state
                 (chip8-app-state-machine app)
                 (case type
                   (:tick :tick)
                   (:key-press :key-press)
                   (:key-release :key-release))))))
    app))

(defun step-chip8-app! (app &key (advance-timers-p t))
  (let ((machine (chip8-app-machine app)))
    (when (and advance-timers-p
               (not (chip8-machine-halted-p machine)))
      (let ((sound-was-active-p
              (plusp (chip8-machine-sound-timer machine))))
        (step-timers! machine)
        (when (and sound-was-active-p
                   (zerop (chip8-machine-sound-timer machine))
                   (chip8-app-audio-output app))
          (reset-chip8-audio-phase! (chip8-app-audio-output app)))))
    (unless (or (chip8-machine-halted-p machine)
                (chip8-app-paused-p app))
      (handler-case
          (unless (chip8-wait-state-kind (chip8-machine-waiting machine))
            (loop repeat (%instructions-per-tick app)
                  do (execute-instruction! machine)
                  when (or (chip8-machine-halted-p machine)
                           (chip8-wait-state-kind (chip8-machine-waiting machine)))
                    do (return)))
        (error (condition)
          (setf (chip8-app-error app) condition
                (chip8-app-quit-p app) t)
          (setf (chip8-app-state-machine app)
                (step-chip8-control-state
                 (chip8-app-state-machine app) :error)))))
    ; Do not send :quit after the control machine reaches a terminal state.
    (when (and (chip8-machine-halted-p machine)
               (not (chip8-app-quit-p app))
               (not (member (chip8-control-state
                             (chip8-app-state-machine app))
                            '("finished" "error")
                            :test #'string=)))
      (setf (chip8-app-quit-p app) t
            (chip8-app-state-machine app)
            (step-chip8-control-state
             (chip8-app-state-machine app) :quit)))
    (let ((wait-kind (chip8-wait-state-kind (chip8-machine-waiting machine)))
          (state-machine (chip8-app-state-machine app)))
      (when (and (string= (cl-dataflow-kit:state-machine-state state-machine)
                    "running")
           wait-kind)
        (setf (chip8-app-state-machine app)
              (step-chip8-control-state
               state-machine (if (eq wait-kind :key)
                                 :key-wait :display-wait)))))
    app))
