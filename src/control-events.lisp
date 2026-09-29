(in-package #:cl-chip8)

(defparameter +chip8-control-events+
  '(:start :tick :key-press :key-release :pause :resume :step :quit :error))

(defstruct (chip8-control-event
            (:constructor make-chip8-control-event (type &optional payload)))
  (type :tick :type keyword)
  (value payload))

(defun chip8-key-event->control-event (event)
  (when event
    (let ((type (key-event-type event))
          (code (key-event-code event)))
      (cond
        ((and (eq type :special) (member code '(:escape :control-c)))
         (make-chip8-control-event :quit code))
        ((eq (key-event-kind event) :press)
         (make-chip8-control-event :key-press code))
        ((eq (key-event-kind event) :release)
         (make-chip8-control-event :key-release code))
        (t nil)))))
