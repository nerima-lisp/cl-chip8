(in-package #:cl-chip8)

(defparameter +default-clock-hz+ 700)

(defstruct (chip8-app (:constructor make-chip8-app))
  machine state-machine renderer decoder render-pipeline
  (clock-hz +default-clock-hz+ :type (integer 1 *))
  (instruction-remainder 0 :type (integer 0 59))
  (paused-p nil :type boolean) (quitp nil :type boolean)
  (error nil :type (or null condition)) stream)
