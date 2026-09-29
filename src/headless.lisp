(in-package #:cl-chip8)

(defun chip8-run-instructions (machine count &key on-wait)
  (check-type count (integer 0 *))
  (let ((start (chip8-machine-instructions machine)))
    (loop repeat count do
      (if (chip8-wait-state-kind (chip8-machine-waiting machine))
          (progn
            (when on-wait (funcall on-wait machine))
            (return))
          (progn
            (execute-instruction! machine)
            (when (chip8-wait-state-kind (chip8-machine-waiting machine))
              (return)))))
    (let ((wait (chip8-machine-waiting machine)))
      (make-chip8-run-result
       :status (if (chip8-wait-state-kind wait) :waiting :completed)
       :executed (- (chip8-machine-instructions machine) start)
       :machine machine
       :continuation (chip8-wait-state-continuation wait)))))

(defun chip8-run-ticks (machine ticks &key (instructions-per-tick 1) on-wait)
  (check-type ticks (integer 0 *))
  (check-type instructions-per-tick (integer 0 *))
  (let ((start (chip8-machine-instructions machine))
        (result nil))
    (loop repeat ticks do
      (step-timers! machine)
      (when (eq (chip8-wait-state-kind (chip8-machine-waiting machine))
                :display)
        (chip8-resume! machine :tick))
      (setf result
            (chip8-run-instructions machine instructions-per-tick
                                    :on-wait on-wait))
      (when (eq (chip8-run-result-status result) :waiting)
        (return)))
    (let ((wait (chip8-machine-waiting machine)))
      (make-chip8-run-result
       :status (if (chip8-wait-state-kind wait) :waiting :completed)
       :executed (- (chip8-machine-instructions machine) start)
       :machine machine
       :continuation (chip8-wait-state-continuation wait)))))
