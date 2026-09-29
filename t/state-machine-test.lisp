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

(defparameter *generated-control-transitions*
  '(("ready" :start "running") ("ready" :quit "finished")
    ("ready" :error "error") ("running" :key-wait "waiting-key")
    ("running" :display-wait "waiting-display") ("running" :pause "paused")
    ("running" :quit "finished") ("running" :error "error")
    ("waiting-key" :key-press "running")
    ("waiting-key" :key-release "running") ("waiting-key" :pause "paused")
    ("waiting-key" :quit "finished") ("waiting-key" :error "error")
    ("waiting-display" :tick "running") ("waiting-display" :pause "paused")
    ("waiting-display" :quit "finished") ("waiting-display" :error "error")
    ("paused" :step "running") ("paused" :resume "running")
    ("paused" :quit "finished") ("paused" :error "error")))

(defparameter *generated-control-states*
  '("ready" "running" "waiting-key" "waiting-display" "paused"
    "finished" "error"))

(defparameter *generated-control-events*
  '(:start :quit :error :key-wait :display-wait :pause :key-press
    :key-release :tick :step :resume))

(defparameter *control-event-cases*
  '((nil nil nil)
    (:special :escape :quit)
    (:special :control-c :quit)
    (:character #\a :key-press)
    (:character #\a :key-release)))

(defparameter *control-cps-wait-cases*
  '((nil :tick :ignored nil)
    (nil :key-press :ignored nil)
    (nil :key-release :ignored nil)
    (:key :tick :error :key)
    (:key :key-press :resumed nil)
    (:key :key-release :resumed nil)
    (:display :tick :resumed nil)
    (:display :key-press :error :display)
    (:display :key-release :error :display)))

(defun %control-cps-test-app (wait-kind)
  (let* ((machine (make-chip8-machine))
         (state-machine (cl-chip8::make-chip8-control-state-machine))
         (app (make-chip8-app :machine machine :state-machine state-machine)))
    (when wait-kind
      (setf (chip8-machine-waiting machine)
            (cl-chip8::make-chip8-wait-state
             :kind wait-kind
             :continuation (lambda (event)
                             (declare (ignore event))
                             t)))
      (setf (cl-dataflow-kit:state-machine-state state-machine)
            (if (eq wait-kind :key) "waiting-key" "waiting-display")))
    app))

(defun generated-transition (state event)
  (let* ((machine (getf state :machine))
         (current (cl-chip8::chip8-control-state machine))
         (transition (find-if (lambda (entry)
                               (and (string= current (first entry))
                                    (eql event (second entry))))
                             *generated-control-transitions*)))
    (if transition
        (list :machine
              (cl-chip8::step-chip8-control-state
               (cl-dataflow-kit:copy-state-machine machine)
               event)
              :signaled nil)
        (handler-case
            (progn
              (cl-chip8::step-chip8-control-state
               (cl-dataflow-kit:copy-state-machine machine)
               event)
              (list :machine machine :signaled nil))
          (error () (list :machine machine :signaled t))))))

(cl-weave:it-property
 "generated control traces accept only declared transitions"
 ((trace
    (cl-weave:gen-state-machine
     (list :machine (cl-chip8::make-chip8-control-state-machine))
     #'generated-transition
     (cl-weave:gen-member
      '(:start :quit :error :key-wait :display-wait :pause :key-press
        :key-release :tick :step :resume))
     :min-length 1 :max-length 16)))
 (let ((events (getf trace :events))
       (states (getf trace :states)))
   (expect (length states) :to-be (1+ (length events)))
   (loop for event in events
         for before in states
         for after in (rest states)
         for current = (cl-chip8::chip8-control-state
                        (getf before :machine))
         for transition = (find-if (lambda (entry)
                                     (and (string= current (first entry))
                                          (eql event (second entry))))
                                   *generated-control-transitions*)
         do (if transition
                (progn
                  (expect (getf after :signaled) :to-be nil)
                  (expect (cl-chip8::chip8-control-state
                           (getf after :machine))
                          :to-equal (third transition)))
                (progn
                  (expect (getf after :signaled) :to-be-truthy)
                  (expect (cl-chip8::chip8-control-state
                           (getf after :machine))
                          :to-equal current))))))

(it "checks every declared and undeclared state/event pair"
  (dolist (state *generated-control-states*)
    (dolist (event *generated-control-events*)
      (let* ((transition (find-if (lambda (entry)
                                    (and (string= state (first entry))
                                         (eql event (second entry))))
                                  *generated-control-transitions*))
             (machine (cl-chip8::make-chip8-control-state-machine)))
        (setf (cl-dataflow-kit:state-machine-state machine) state)
        (if transition
            (expect (cl-chip8::chip8-control-state
                     (cl-chip8::step-chip8-control-state machine event))
                    :to-equal
                    (third transition))
              (signals error
              (cl-chip8::step-chip8-control-state machine event)))))))

(cl-weave:it-isolated
    "maps every key event variant through the control-event table"
    (:systems ("cl-chip8/test") :timeout 20)
  (dolist (case *control-event-cases*)
    (destructuring-bind (type code expected-type) case
      (let ((event (and type
                        (cl-tty-kit:make-key-event
                         :type type :code code
                         :kind (if (eq expected-type :key-release)
                                   :release
                                   :press)))))
        (let ((control-event
                (cl-chip8::chip8-key-event->control-event event)))
          (if expected-type
              (progn
                (expect (cl-chip8::chip8-control-event-type control-event)
                        :to-be expected-type)
                (expect (cl-chip8::chip8-control-event-value control-event)
                        :to-equal code))
              (expect control-event :to-be nil)))))))

(cl-weave:it-isolated
    "drives every control-cps event across each wait state"
    (:systems ("cl-chip8/test") :timeout 20)
  (dolist (case *control-cps-wait-cases*)
    (destructuring-bind (wait-kind type expected-result expected-wait) case
      (let* ((app (%control-cps-test-app wait-kind))
             (event (cl-chip8::make-chip8-control-event
                     type (when (member type '(:key-press :key-release)) 5)))
             (result (handler-case
                         (progn
                           (cl-chip8::resume-chip8-app app event)
                           :ok)
                       (chip8-cps-error () :error))))
        (case expected-result
          (:error (expect result :to-be :error))
          (:resumed
           (expect result :to-be :ok)
           (expect (wait-kind (chip8-app-machine app)) :to-be nil)
           (expect (cl-chip8::chip8-control-state
                    (chip8-app-state-machine app))
                   :to-equal "running"))
          (:ignored
           (expect result :to-be :ok)
           (expect (wait-kind (chip8-app-machine app)) :to-be expected-wait)
           (expect (cl-chip8::chip8-control-state
                    (chip8-app-state-machine app))
                   :to-equal (if expected-wait
                                 (if (eq expected-wait :key)
                                     "waiting-key"
                                     "waiting-display")
                                 "ready"))))))))

(describe
  "control state transition table"
  (it
    "walks the ready, run, pause, wait, and finished states"
    (let ((state-machine (cl-chip8::make-chip8-control-state-machine)))
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
    (let ((state-machine (cl-chip8::make-chip8-control-state-machine)))
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
