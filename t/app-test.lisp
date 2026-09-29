(in-package #:cl-chip8/test)

(describe
  "application worker scheduling"
  (it
    "distributes the configured clock over exactly sixty ticks"
    (dolist (clock-hz '(1 59 60 700))
      (let ((app (make-chip8-app :clock-hz clock-hz)))
        (expect
          (loop repeat 60 sum (cl-chip8::%instructions-per-tick app))
          :to-be
          clock-hz))))
  (it
    "keeps the scheduler remainder bounded"
    (let ((app (make-chip8-app :clock-hz 700)))
      (loop repeat 120 do
        (cl-chip8::%instructions-per-tick app)
        (expect (< (cl-chip8::chip8-app-instruction-remainder app) 60)
                :to-be
                t)))))

(describe "application error handling"
  (it "steps the error event when instruction execution signals"
    (let* ((machine (make-chip8-machine))
           (app (make-chip8-app
                 :machine machine
                 :state-machine (make-chip8-control-state-machine)
                 :clock-hz 60)))
      (setf (cl-dataflow-kit:state-machine-state
             (chip8-app-state-machine app))
            "running")
      (setf (chip8-machine-pc machine) #xfff)
      (cl-chip8::step-chip8-app! app)
      (expect (chip8-app-error app) :to-be-type-of 'error)
      (expect (chip8-control-state (chip8-app-state-machine app))
              :to-equal "error")
      (expect (chip8-app-quit-p app) :to-be-truthy))))
