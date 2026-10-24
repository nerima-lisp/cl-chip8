(in-package #:cl-chip8)

(defstruct (chip8-app (:constructor make-chip8-app))
  machine state-machine renderer render-state decoder render-pipeline
  (clock-hz +default-clock-hz+ :type (integer 1 *))
  (instruction-remainder 0 :type (integer 0 59))
  (paused-p nil :type boolean) (quit-p nil :type boolean)
  (error nil :type (or null condition))
  audio-output
  (audio-mode :off :type (member :auto :pcm :bell :off))
  (last-audio-sound-timer 0 :type integer)
  (last-audio-bell-time nil :type (or null integer))
  stream started-at)
