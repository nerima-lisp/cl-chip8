(in-package #:cl-chip8/test)

(defun %app-test-event (type code &key (kind :press))
  (cl-tty-kit:make-key-event :type type :code code :kind kind))

(describe
  "application input helpers"
  (it
    "reads every immediately available character and stops at EOF"
    (let ((stream (make-string-input-stream "abc")))
      (expect (cl-chip8::%read-available-string stream) :to-equal "abc")
      (expect (cl-chip8::%read-available-string stream) :to-equal "")))
  (it
    "polls a decoder with available input and with an explicit EOF chunk"
    (let ((decoder (cl-tty-kit:make-input-decoder)))
      (with-open-stream (stream (make-string-input-stream "q"))
        (let ((events (cl-chip8::%poll-input-events decoder stream)))
          (expect (length events) :to-be 1)
          (expect (cl-chip8::key-event-type (first events)) :to-be :character)
          (expect (cl-chip8::key-event-code (first events)) :to-be #\q)))
      (expect (cl-chip8::%poll-input-events decoder
                                             (make-string-input-stream ""))
              :to-equal nil)))
  (it-each ((#\1 1) (#\Q 4) (#\v #xf))
      "maps keypad character ~C to CHIP-8 key ~D"
      (character expected)
    (expect (cl-chip8::%mapped-key
             (%app-test-event :character character))
            :to-be expected))
  (it
    "returns NIL for unsupported and special events"
    (expect (cl-chip8::%mapped-key (%app-test-event :character #\g))
            :to-be nil)
    (expect (cl-chip8::%mapped-key (%app-test-event :special :escape))
            :to-be nil)))

(describe
  "application key handling"
  (it
    "toggles pause and resume through the control state machine"
    (let ((app (make-chip8-app
                :machine (make-chip8-machine)
                :state-machine (cl-chip8::make-chip8-control-state-machine))))
      (setf (chip8-app-state-machine app)
            (cl-chip8::step-chip8-control-state
             (chip8-app-state-machine app) :start))
      (expect (cl-chip8::%apply-control-key!
               app (%app-test-event :character #\p))
              :to-be t)
      (expect (chip8-app-paused-p app) :to-be t)
      (expect (cl-chip8::chip8-control-state
               (chip8-app-state-machine app))
              :to-equal "paused")
      (cl-chip8::%apply-control-key! app (%app-test-event :character #\P))
      (expect (chip8-app-paused-p app) :to-be nil)
      (expect (cl-chip8::chip8-control-state
               (chip8-app-state-machine app))
              :to-equal "running")))
  (it
    "resets the machine and control state on backspace"
    (let* ((machine (make-chip8-machine))
           (app (make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine))))
      (setf (chip8-machine-pc machine) #x300
            (chip8-app-paused-p app) t)
      (cl-chip8::%apply-control-key!
       app (%app-test-event :special :backspace))
      (expect (chip8-machine-pc machine) :to-be +initial-pc+)
      (expect (chip8-app-paused-p app) :to-be nil)
      (expect (cl-chip8::chip8-control-state
               (chip8-app-state-machine app))
              :to-equal "ready")))
  (it
    "steps one instruction while paused without resuming"
    (let* ((machine (make-chip8-machine))
           (app (make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine))))
      (setf (aref (chip8-machine-memory machine) #x200) #x60
            (aref (chip8-machine-memory machine) #x201) #x01
            (chip8-app-paused-p app) t
            (cl-dataflow-kit:state-machine-state
             (chip8-app-state-machine app))
            "paused")
      (cl-chip8::%apply-control-key! app (%app-test-event :character #\n))
      (expect (chip8-machine-register machine 0) :to-be 1)
      (expect (chip8-app-paused-p app) :to-be t)
      (expect (cl-chip8::chip8-control-state
               (chip8-app-state-machine app))
              :to-equal "running")))
  (it
    "applies mapped press and release events to the machine keypad"
    (let* ((machine (make-chip8-machine))
           (app (make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine)))
           (event (%app-test-event :character #\x)))
      (expect (cl-chip8::%apply-key-event! app event) :to-be app)
      (expect (key-down-p machine 0) :to-be t)
      (cl-chip8::%apply-key-event!
       app (%app-test-event :character #\x :kind :release))
      (expect (key-down-p machine 0) :to-be nil)))
  (it
    "marks the app finished for Escape and returns the app"
    (let ((app (make-chip8-app
                :machine (make-chip8-machine)
                :state-machine (cl-chip8::make-chip8-control-state-machine))))
      (expect (cl-chip8::%apply-key-event!
               app (%app-test-event :special :escape))
              :to-be app)
      (expect (chip8-app-quit-p app) :to-be t)
      (expect (cl-chip8::chip8-control-state
               (chip8-app-state-machine app))
              :to-equal "finished")))
  (it
    "applies a sequence and returns the app"
    (let ((app (make-chip8-app
                :machine (make-chip8-machine)
                :state-machine (cl-chip8::make-chip8-control-state-machine)))
          (events (list (%app-test-event :character #\1)
                        (%app-test-event :character #\2))))
      (expect (cl-chip8::%apply-key-events! app events) :to-be app)
      (expect (pressed-keys (chip8-app-machine app)) :to-equal '(1 2)))))

(describe
  "application advancement and completion"
  (it
    "starts a ready app and executes one instruction without a terminal"
    (let* ((machine (make-chip8-machine))
           (app (make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine)
                 :decoder (cl-tty-kit:make-input-decoder)
                 :clock-hz 60))
           (*standard-input* (make-string-input-stream "")))
      (setf (aref (chip8-machine-memory machine) #x200) #x60
            (aref (chip8-machine-memory machine) #x201) #x01)
      (expect (cl-chip8::%advance-chip8! app) :to-be app)
      (expect (chip8-machine-register machine 0) :to-be 1)
      (expect (chip8-machine-pc machine) :to-be #x202)
      (expect (cl-chip8::chip8-control-state
               (chip8-app-state-machine app))
              :to-equal "running")))
  (it-each ((nil "running" nil)
            (t "running" t)
            (nil "finished" t)
            (nil "error" t))
      "recognizes finished state ~S with quit flag ~S"
      (quit-p state expected)
    (let ((app (make-chip8-app
                :machine (make-chip8-machine)
                :state-machine (cl-chip8::make-chip8-control-state-machine)
                :quit-p quit-p)))
      (setf (cl-dataflow-kit:state-machine-state
             (chip8-app-state-machine app)) state)
      (expect (not (null (cl-chip8::%chip8-app-finished-p app)))
              :to-be expected))))

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

(defun %pty-rom-path (name)
  (merge-pathnames
   (format nil "cl-chip8-pty-~A-~D.ch8" name (random 1000000))
   (uiop:temporary-directory)))

(defun %write-pty-rom (path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                          :element-type '(unsigned-byte 8))
    ;; Draw one visible pixel, increment V0, and loop. This gives the terminal
    ;; session both observable screen output and a continuously live process.
    (dolist (byte '(#x00 #xe0 #x60 #x00 #x61 #x00 #xa3 #x00 #xd0 #x11
                    #x70 #x01 #x12 #x08))
      (write-byte byte stream)))
  path)

(defun %pty-output-line-value (output label)
  (let ((prefix (concatenate 'string label "=")))
    (loop for line in (uiop:split-string output :separator '(#\Newline))
          for start = (search prefix line)
          when start
            return (string-right-trim '(#\Return #\Newline #\Space)
                                       (subseq line (+ start (length prefix)))))))

(defun %pty-stty-lflag (value)
  (let* ((prefix "lflag=")
         (start (search prefix value))
         (end (and start (position #\: value :start (+ start (length prefix))))))
    (and start end
         (logand #xffff
                 (parse-integer value :start (+ start (length prefix)) :end end
                                :radix 16)))))

(defun %pty-restoration-command (script rom)
  (format nil
          "before=$(stty -g); printf 'BEFORE=%s\\n' \"$before\"; ~A --script ~A ~A; status=$?; after=$(stty -g); printf 'AFTER=%s\\nSTATUS=%s\\n' \"$after\" \"$status\"; exit $status"
          (%pty-sbcl-program) (namestring script) (namestring rom)))

(%it-pty-isolated "PTY renders a ROM and restores raw mode on Escape"
    (:systems ("cl-chip8/test") :timeout 60)
  (let* ((rom (%write-pty-rom (%pty-rom-path "render")))
         (script (%write-pty-test-script (%pty-test-script "render"))))
    (unwind-protect
         (%with-test-pty (pty :program "sh"
                               :args (list "-c"
                                           (%pty-restoration-command
                                            script rom)))
           (multiple-value-bind (initial ready-p)
               (%pty-wait-for-terminal pty)
             (expect (if ready-p
                         t
                         (list :terminal-output initial
                               :pty-alive-p (cl-tty-kit:pty-alive-p pty)
                               :pty-exit-code (cl-tty-kit:pty-exit-code pty)))
                     :to-be t)
             (%pty-expect-alive pty initial)
             ;; The terminal session enables enhanced keyboard reports;
             ;; encode Escape as the cl-tty-kit CSI-u key report.
             (cl-tty-kit:pty-write pty (format nil "~C[27u" #\Escape))
             (multiple-value-bind (output done-p exit-code)
                 (%pty-wait-for-exit pty :timeout 60)
               (let ((output (concatenate 'string initial output)))
                 (%pty-expect-done pty output done-p exit-code)
                 (expect exit-code :to-be 0)
                 (expect output :to-contain (string #\Escape))
                 (expect output :to-contain "BEFORE=")
                 (expect output :to-contain "AFTER=")
                 (let ((before (%pty-output-line-value output "BEFORE"))
                       (after (%pty-output-line-value output "AFTER")))
                   (expect before :to-be-truthy)
                   (expect after :to-be-truthy))
                 (expect output :to-contain
                         (format nil "~C[?1049l" #\Escape))
                 (expect output :to-be-type-of 'string))))))
      (when (probe-file rom) (delete-file rom))
      (when (probe-file script) (delete-file script))))
