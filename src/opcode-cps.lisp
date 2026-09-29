(in-package #:cl-chip8)

(define-condition chip8-cps-error (chip8-error)
  ((phase :initarg :phase :reader chip8-cps-error-phase)
   (cause :initarg :cause :reader chip8-cps-error-cause)))

(defun %chip8-cps-error (cause)
  (error 'chip8-cps-error :phase :resume :cause cause))

(defun %validate-resume-event (event)
  (cond
    ((eq event :tick) event)
    ((and (consp event)
          (null (cddr event))
          (member (first event) '(:key-down :key-up) :test #'eq))
     (handler-case
         (progn (check-type (second event) chip8-key) event)
       (type-error () (%chip8-cps-error :invalid-event))))
    (t (%chip8-cps-error :invalid-event))))

(defun chip8-resume! (machine event)
  "Apply EVENT to the continuation stored in MACHINE's waiting slot."
  (let ((wait (chip8-machine-waiting machine)))
    (unless (chip8-wait-state-kind wait)
      (%chip8-cps-error :not-waiting))
    (let ((validated (%validate-resume-event event))
          (continuation (chip8-wait-state-continuation wait)))
      (unless continuation
        (%chip8-cps-error :missing-continuation))
      (when (and (eq (chip8-wait-state-kind wait) :display)
                 (not (eq validated :tick)))
        (%chip8-cps-error :invalid-event))
      (when (and (eq (chip8-wait-state-kind wait) :key)
                 (eq validated :tick))
        (%chip8-cps-error :invalid-event))
      (when (funcall continuation validated)
        (setf (chip8-machine-waiting machine) (make-chip8-wait-state))))
    machine))
