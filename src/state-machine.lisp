(in-package #:cl-chip8)

(defparameter *chip8-state-machine*
  (cl-dataflow-kit:define-state-machine
    (:initial-state "ready" :history-limit 64)
    ("ready" :start "running")
    ("ready" :quit "finished")
    ("ready" :error "error")
    ("running" :key-wait "waiting-key")
    ("running" :display-wait "waiting-display")
    ("running" :pause "paused")
    ("running" :quit "finished")
    ("running" :error "error")
    ("waiting-key" :key-press "running")
    ("waiting-key" :key-release "running")
    ("waiting-key" :pause "paused")
    ("waiting-key" :quit "finished")
    ("waiting-key" :error "error")
    ("waiting-display" :tick "running")
    ("waiting-display" :pause "paused")
    ("waiting-display" :quit "finished")
    ("waiting-display" :error "error")
    ("paused" :step "running")
    ("paused" :resume "running")
    ("paused" :quit "finished")
    ("paused" :error "error"))
  "Immutable definition of the control states used by CHIP8-APP.")

(defun make-chip8-control-state-machine ()
  (cl-dataflow-kit:copy-state-machine *chip8-state-machine*))

(defun chip8-control-state (machine)
  (cl-dataflow-kit:state-machine-state machine))

(defun step-chip8-control-state (machine event &key context)
  (cl-dataflow-kit:step-state-machine
   machine
   (if (chip8-control-event-p event)
       (chip8-control-event-type event)
       event)
   :context context))
