(in-package #:cl-chip8/test)

(defun state-machine-test-opcodes (machine &rest opcodes)
  (load-rom machine
            (coerce
             (loop for opcode in opcodes append
               (list (ldb (byte 8 8) opcode) (ldb (byte 8 0) opcode)))
             '(vector (unsigned-byte 8)))
            :address (chip8-machine-pc machine)))

(defun wait-kind (machine)
  (cl-chip8::chip8-wait-state-kind (chip8-machine-waiting machine)))

(describe
  "control state transition table"
  (it
    "walks the ready, run, pause, wait, and finished states"
    (let ((state-machine (cl-chip8::make-chip8-app-state-machine)))
      (dolist (transition '((:start "running") (:pause "paused")
                            (:step "running") (:key-wait "waiting-key")
                            (:key-press "running") (:display-wait "waiting-display")
                            (:tick "running") (:quit "finished")))
        (setf state-machine
              (cl-chip8::step-chip8-control-state state-machine (first transition)))
        (expect (cl-chip8::chip8-control-state state-machine)
                :to-equal
                (second transition)))))
  (it
    "rejects an event not present in the transition table"
    (let ((state-machine (cl-chip8::make-chip8-app-state-machine)))
      (signals error
        (cl-chip8::step-chip8-control-state state-machine :resume)))))

(describe
  "headless state transitions"
  (it-each
    ((:reset :completed) (:step :completed) (:pause :waiting)
     (:resume :completed) (:reset-after-wait :completed))
    "reaches the expected state from the transition table"
    (transition expected)
    (let ((machine (make-chip8-machine)))
      (case transition
        (:reset
         (chip8-reset! machine))
        (:step
         (state-machine-test-opcodes machine #x6001)
         (let ((result (chip8-run-instructions machine 1)))
           (expect (chip8-run-result-status result) :to-be expected)))
        (:pause
         (state-machine-test-opcodes machine #xF00A)
         (let ((result (chip8-run-instructions machine 1)))
           (expect (chip8-run-result-status result) :to-be expected)
           (expect (wait-kind machine) :to-be :key)))
        (:resume
         (state-machine-test-opcodes machine #xF00A)
         (chip8-run-instructions machine 1)
         (chip8-resume! machine '(:key-down 5))
         (let ((result (chip8-run-instructions machine 0)))
           (expect (chip8-run-result-status result) :to-be expected)
           (expect (chip8-machine-register machine 0) :to-be 5)))
        (:reset-after-wait
         (state-machine-test-opcodes machine #xF00A)
         (chip8-run-instructions machine 1)
         (chip8-reset! machine)
         (expect (wait-kind machine) :to-be nil)
         (expect (chip8-machine-pc machine) :to-be +initial-pc+)))
      (when (eq transition :reset)
        (expect (chip8-machine-pc machine) :to-be +initial-pc+))))
  (it
    "rejects resume when the machine is not paused"
    (signals chip8-cps-error
      (chip8-resume! (make-chip8-machine) :tick)))
  (it
    "keeps a key wait paused for unrelated events"
    (let ((machine (make-chip8-machine)))
      (state-machine-test-opcodes machine #xF10A)
      (chip8-run-instructions machine 1)
      (signals chip8-cps-error (chip8-resume! machine '(:other 5)))
      (expect (wait-kind machine) :to-be :key)
      (expect (chip8-machine-pc machine) :to-be +initial-pc+)))
  (it
    "resumes a display wait only on a tick"
    (let ((machine (make-chip8-machine
                    :quirks (make-chip8-quirks :display-wait :wait))))
      (state-machine-test-opcodes machine #xA300 #xD011 #x6001)
      (setf (aref (chip8-machine-memory machine) #x300) #x80)
      (setf (chip8-machine-register machine 0) 0
            (chip8-machine-register machine 1) 0)
      (chip8-run-instructions machine 2)
      (expect (wait-kind machine) :to-be :display)
      (signals chip8-cps-error (chip8-resume! machine :key-down))
      (expect (wait-kind machine) :to-be :display)
      (chip8-resume! machine :tick)
      (expect (wait-kind machine) :to-be nil)
      (expect (chip8-machine-pc machine) :to-be #x204)))
  (it
    "reports display and key waits through the headless runner"
    (let ((machine (make-chip8-machine
                    :quirks (make-chip8-quirks :display-wait :wait))))
      (state-machine-test-opcodes machine #xA300 #xD011)
      (setf (aref (chip8-machine-memory machine) #x300) #x80)
      (let ((result (chip8-run-instructions machine 2)))
        (expect (chip8-run-result-status result) :to-be :waiting)
        (expect (wait-kind machine) :to-be :display)))))
