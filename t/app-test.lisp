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
    "ignores pause when the app is ready"
    (let ((app (make-chip8-app
                :machine (make-chip8-machine)
                :state-machine (cl-chip8::make-chip8-control-state-machine))))
      (expect (cl-chip8::%apply-control-key!
               app (%app-test-event :character #\p))
              :to-be t)
      (expect (chip8-app-paused-p app) :to-be nil)
      (expect (cl-chip8::chip8-control-state
               (chip8-app-state-machine app))
              :to-equal "ready")))
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
            (chip8-machine-delay-timer machine) 2
            (chip8-machine-sound-timer machine) 2
            (cl-dataflow-kit:state-machine-state
             (chip8-app-state-machine app))
            "paused")
      (cl-chip8::%apply-control-key! app (%app-test-event :character #\n))
      (expect (chip8-machine-register machine 0) :to-be 1)
      (expect (chip8-machine-delay-timer machine) :to-be 2)
      (expect (chip8-machine-sound-timer machine) :to-be 2)
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
    "uses the concurrent render pipeline when rendering an app"
    (with-chip8-render-pipeline (pipeline :parallelism 1 :parallel-threshold 1)
      (let ((app (make-chip8-app
                  :machine (make-chip8-machine)
                  :renderer (cl-tty-kit:make-renderer +screen-width+ +screen-height+)
                  :render-pipeline pipeline)))
        (cl-chip8::%render-chip8-app! app)
        (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline)
                :to-be 16)
        (expect (cl-chip8::chip8-render-pipeline-serial-rows pipeline)
                :to-be 0))))
  (it
  "renders 128x64 hires values directly with half-block palette colors"
  (let* ((machine (make-chip8-machine :platform :schip))
         (renderer (cl-tty-kit:make-renderer +screen-width+ +screen-height+))
         (render-state (cl-chip8::make-chip8-render-state))
         (app (make-chip8-app
               :machine machine :renderer renderer
               :render-state render-state)))
    (set-chip8-machine-resolution! machine :hires)
    (let ((cl-chip8::*chip8-render-palette*
            (copy-seq cl-chip8::*chip8-render-palette*)))
      (cl-chip8:set-chip8-render-palette!
       '("#000000" "#ff0000" "#00ff00" "#0000ff"))
      (let ((framebuffer (chip8-machine-framebuffer machine)))
        (setf (aref framebuffer 2 3) 1
              (aref framebuffer 3 3) 2))
      (cl-chip8::%refresh-chip8-display! app 130 34)
      (let ((snapshot (chip8-framebuffer-snapshot machine)))
        (expect (array-dimensions snapshot) :to-equal '(64 128))
        (expect (aref snapshot 2 3) :to-be 1)
        (expect (aref snapshot 3 3) :to-be 2))
      (cl-chip8::%render-chip8-app! app)
      (let* ((screen (cl-tty-kit:renderer-screen renderer))
             (cell
               (cl-tty-kit:screen-cell
                screen
                (+ cl-chip8::+playfield-origin-x+ 3)
                (+ cl-chip8::+playfield-origin-y+ 1))))
        (expect (cl-tty-kit:screen-width screen) :to-be 130)
        (expect (cl-tty-kit:screen-height screen) :to-be 34)
        (expect (cl-tty-kit:cell-char cell) :to-be (code-char #x2580))
        (expect (cl-tty-kit:cell-style cell)
                :to-equal
                (list
                 (cl-tty-kit:style-fg
                  (cl-tty-kit:rgb-to-256 255 0 0))
                 (cl-tty-kit:style-bg
                  (cl-tty-kit:rgb-to-256 0 255 0))))))))
  (it
  "blocks advancement while too small and resumes after recovery"
  (let* ((machine (make-chip8-machine :platform :schip))
         (renderer (cl-tty-kit:make-renderer +screen-width+ +screen-height+))
         (decoder (cl-tty-kit:make-input-decoder))
         (app (make-chip8-app
               :machine machine
               :state-machine (cl-chip8::make-chip8-control-state-machine)
               :renderer renderer
               :decoder decoder
               :clock-hz 60))
         (*standard-input* (make-string-input-stream "")))
    (set-chip8-machine-resolution! machine :hires)
    (setf (aref (chip8-machine-memory machine) #x200) #x60
          (aref (chip8-machine-memory machine) #x201) #x01
          (cl-dataflow-kit:state-machine-state
           (chip8-app-state-machine app)) "running")
    (cl-chip8::%refresh-chip8-display! app 65 17)
    (expect (cl-chip8::chip8-app-display-too-small-p app) :to-be t)
    (expect (cl-chip8::chip8-app-display-mode app) :to-be :too-small)
    (expect (cl-tty-kit:screen-width (cl-tty-kit:renderer-screen renderer))
            :to-be 65)
    (expect (cl-tty-kit:screen-height (cl-tty-kit:renderer-screen renderer))
            :to-be 17)
    (expect
      (cl-tty-kit:cell-char
       (cl-tty-kit:screen-cell
        (cl-tty-kit:renderer-screen renderer) 0 0))
      :to-be #\T)
    (cl-chip8::%advance-chip8! app 65 17)
    (expect (chip8-machine-pc machine) :to-be #x200)
    (expect (chip8-machine-register machine 0) :to-be 0)
    (setf (chip8-app-paused-p app) t
          (cl-dataflow-kit:state-machine-state
           (chip8-app-state-machine app)) "paused")
    (cl-chip8::%advance-chip8! app 66 18)
    (expect (cl-chip8::chip8-app-display-too-small-p app) :to-be nil)
    (expect (cl-chip8::chip8-app-display-mode app) :to-be :braille)
    (expect (chip8-app-paused-p app) :to-be t)
    (expect (cl-chip8::chip8-control-state
             (chip8-app-state-machine app))
            :to-equal "paused")
    (expect (cl-tty-kit:screen-width (cl-tty-kit:renderer-screen renderer))
            :to-be 66)
    (expect (cl-tty-kit:screen-height (cl-tty-kit:renderer-screen renderer))
            :to-be 18)
    (expect (chip8-machine-pc machine) :to-be #x200)
    (expect (chip8-machine-register machine 0) :to-be 0)
    (cl-chip8::%apply-control-key!
     app (%app-test-event :character #\o))
    (cl-chip8::%advance-chip8! app 66 18)
    (expect (chip8-machine-pc machine) :to-be #x202)
    (expect (chip8-machine-register machine 0) :to-be 1)))
  (it
  "switches renderer modes and sizes for the available terminal geometry"
  (let* ((machine (make-chip8-machine :platform :schip))
         (renderer (cl-tty-kit:make-renderer +screen-width+ +screen-height+))
         (render-state (cl-chip8::make-chip8-render-state))
         (app (make-chip8-app
               :machine machine :renderer renderer
               :render-state render-state)))
    (set-chip8-machine-resolution! machine :hires)
    (setf (cl-chip8::chip8-render-state-framebuffer render-state)
          (make-array '(32 64) :element-type '(unsigned-byte 2))
          (cl-chip8::chip8-render-state-frame-count render-state) 7)
    (cl-chip8::%refresh-chip8-display! app 130 34)
    (expect (cl-chip8::chip8-app-display-mode app) :to-be :half-block)
    (expect (cl-tty-kit:screen-width (cl-tty-kit:renderer-screen renderer))
            :to-be 130)
    (expect (cl-tty-kit:screen-height (cl-tty-kit:renderer-screen renderer))
            :to-be 34)
    (expect (cl-chip8::chip8-render-state-framebuffer render-state) :to-be nil)
    (expect (cl-chip8::chip8-render-state-frame-count render-state) :to-be 7)
    (setf (cl-chip8::chip8-render-state-framebuffer render-state)
          (make-array '(64 128) :element-type '(unsigned-byte 2)))
    (cl-chip8::%refresh-chip8-display! app 66 34)
    (expect (cl-chip8::chip8-app-display-mode app) :to-be :quarter-block)
    (expect (cl-tty-kit:screen-width (cl-tty-kit:renderer-screen renderer))
            :to-be 66)
    (expect (cl-tty-kit:screen-height (cl-tty-kit:renderer-screen renderer))
            :to-be 34)
    (expect (cl-chip8::chip8-render-state-framebuffer render-state) :to-be nil)
    (expect (cl-chip8::chip8-render-state-frame-count render-state) :to-be 7)
    (setf (cl-chip8::chip8-render-state-framebuffer render-state)
          (make-array '(64 128) :element-type '(unsigned-byte 2)))
    (cl-chip8::%refresh-chip8-display! app 66 18)
    (expect (cl-chip8::chip8-app-display-mode app) :to-be :braille)
    (expect (cl-tty-kit:screen-width (cl-tty-kit:renderer-screen renderer))
            :to-be 66)
    (expect (cl-tty-kit:screen-height (cl-tty-kit:renderer-screen renderer))
            :to-be 18)
    (expect (cl-chip8::chip8-render-state-framebuffer render-state) :to-be nil)
    (set-chip8-machine-resolution! machine :lores)
    (cl-chip8::%refresh-chip8-display! app 66 18)
    (expect (cl-chip8::chip8-app-display-mode app) :to-be :lores)
    (expect (cl-tty-kit:screen-width (cl-tty-kit:renderer-screen renderer))
            :to-be 66)
    (expect (cl-tty-kit:screen-height (cl-tty-kit:renderer-screen renderer))
            :to-be 18)))
  (it
    "renders XO-CHIP lores with palette-aware half-block cells"
    (let* ((machine (make-chip8-machine :platform :xo-chip))
           (render-state (cl-chip8::make-chip8-render-state))
           (output (make-string-output-stream))
           (*standard-output* output)
           (renderer (cl-tty-kit:make-renderer 50 12))
           (app (make-chip8-app
                 :machine machine
                 :renderer renderer
                 :render-state render-state
                 :display-columns 50
                 :display-rows 12)))
      (cl-chip8::%refresh-chip8-display! app 66 18)
      (setf (aref (chip8-machine-framebuffer machine) 0 0) 2
            (aref (chip8-machine-framebuffer machine) 2 0) 3)
      (cl-chip8::%render-chip8-app! app)
      (let ((cell (cl-tty-kit:screen-cell
                   (cl-tty-kit:renderer-screen renderer) 1 1)))
        (expect (cl-chip8::chip8-app-display-mode app) :to-be :lores)
        (expect (cl-chip8::chip8-render-state-display-mode render-state)
                :to-be :half-block)
        (expect (cl-tty-kit:cell-char cell) :to-be (code-char #x2580))
        (expect (cl-tty-kit:cell-style cell)
                :to-equal
                (cl-tty-kit:make-style
                 (cl-tty-kit:style-fg
                  (aref cl-chip8::*chip8-render-palette* 2))
                 (cl-tty-kit:style-bg
                  (aref cl-chip8::*chip8-render-palette* 3))))
        (expect
         (cl-chip8::%chip8-app-render-mode
          (make-chip8-app :machine (make-chip8-machine :platform :modern))
          :lores)
         :to-be :lores)
        (expect
         (cl-tty-kit:screen-width (cl-tty-kit:renderer-screen renderer))
         :to-be 66)
        (expect
         (cl-tty-kit:screen-height (cl-tty-kit:renderer-screen renderer))
         :to-be 18))))
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
  (it-each
    ((:lores :display) (:hires nil))
    "applies :schip-legacy display waiting in ~A mode"
    (resolution expected-wait)
    (let* ((machine (make-chip8-machine :platform :schip-legacy))
           (app (make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine)
                 :decoder (cl-tty-kit:make-input-decoder)
                 :clock-hz 60)))
      (when (eq resolution :hires)
        (set-chip8-machine-resolution! machine :hires))
      (load-rom machine #(#xa3 #x00 #xd0 #x11 #x60 #x01 #x61 #x02))
      (setf (aref (chip8-machine-memory machine) #x300) #x80)
      (let ((*standard-input* (make-string-input-stream "")))
        (cl-chip8::%advance-chip8! app)
        (cl-chip8::%advance-chip8! app)
        (expect
          (cl-chip8::chip8-wait-state-kind
           (chip8-machine-waiting machine))
          :to-be
          expected-wait)
        (expect (chip8-control-state (chip8-app-state-machine app))
                :to-equal
                (if expected-wait "waiting-display" "running"))
        (if expected-wait
            (progn
              (expect (chip8-machine-pc machine) :to-be #x202)
              (expect (chip8-machine-instructions machine) :to-be 2)
              (cl-chip8::%advance-chip8! app)
              (expect
                (cl-chip8::chip8-wait-state-kind
                 (chip8-machine-waiting machine))
                :to-be
                nil)
              (expect (chip8-machine-register machine 0) :to-be 1)
              (expect (chip8-machine-pc machine) :to-be #x206)
              (expect (chip8-machine-instructions machine) :to-be 3)
              (cl-chip8::%advance-chip8! app)
              (expect (chip8-machine-register machine 1) :to-be 2)
              (expect (chip8-machine-pc machine) :to-be #x208)
              (expect (chip8-machine-instructions machine) :to-be 4))
            (progn
              (expect (chip8-machine-pc machine) :to-be #x204)
              (expect (chip8-machine-instructions machine) :to-be 2)
              (cl-chip8::%advance-chip8! app)
              (expect (chip8-machine-register machine 0) :to-be 1)
              (expect (chip8-machine-pc machine) :to-be #x206)
              (expect (chip8-machine-instructions machine) :to-be 3))))))
  (it
    "renders a lores draw while waiting before the next real-time advance resumes it"
    (let* ((machine (make-chip8-machine :platform :schip-legacy))
           (renderer (cl-tty-kit:make-renderer +screen-width+ +screen-height+))
           (app (make-chip8-app
                 :machine machine
                 :renderer renderer
                 :render-state (cl-chip8::make-chip8-render-state)
                 :state-machine (cl-chip8::make-chip8-control-state-machine)
                 :decoder (cl-tty-kit:make-input-decoder)
                 :clock-hz 60))
           (render-count 0)
           (waiting-state nil)
           (waiting-kind nil)
           (waiting-pc nil)
           (waiting-instructions nil)
           (waiting-cell nil)
           (waiting-frame nil)
           (stream (make-string-output-stream))
           (*standard-input* (make-string-input-stream "")))
      (load-rom machine #(#xa3 #x00 #xd0 #x11 #x60 #x01))
      (setf (aref (chip8-machine-memory machine) #x300) #x80)
      (cl-tty-kit:tick-loop-run-realtime
       app
       #'cl-chip8::%advance-chip8!
       (lambda (state)
         (incf render-count)
         (let ((frame (cl-chip8::%render-chip8-app! state)))
           (when (= render-count 2)
             (setf waiting-state
                   (chip8-control-state (chip8-app-state-machine state))
                   waiting-kind
                   (cl-chip8::chip8-wait-state-kind
                    (chip8-machine-waiting machine))
                   waiting-pc (chip8-machine-pc machine)
                   waiting-instructions (chip8-machine-instructions machine)
                   waiting-cell
                   (cl-tty-kit:cell-char
                    (cl-tty-kit:screen-cell
                     (cl-tty-kit:renderer-screen renderer)
                     cl-chip8::+playfield-origin-x+
                     cl-chip8::+playfield-origin-y+))
                   waiting-frame frame))
           frame))
       (lambda (state)
         (declare (ignore state))
         (>= render-count 3))
       :stream stream
       :interval 1/1000)
      (expect render-count :to-be 3)
      (expect waiting-state :to-equal "waiting-display")
      (expect waiting-kind :to-be :display)
      (expect waiting-pc :to-be #x202)
      (expect waiting-instructions :to-be 2)
      (expect waiting-cell :to-be (code-char #x2580))
      (expect (and (stringp waiting-frame)
                   (plusp (length waiting-frame)))
              :to-be
              t)
      (expect (chip8-control-state (chip8-app-state-machine app))
              :to-equal
              "running")
      (expect (cl-chip8::chip8-wait-state-kind
               (chip8-machine-waiting machine))
              :to-be
              nil)
      (expect (chip8-machine-register machine 0) :to-be 1)
      (expect (chip8-machine-pc machine) :to-be #x206)
      (expect (chip8-machine-instructions machine) :to-be 3)
      (let ((output (get-output-stream-string stream)))
        (expect (and (stringp waiting-frame)
                     (search waiting-frame output))
                :to-be-truthy))))
  (it
    "halts the app cleanly on SCHIP 00FD"
    (let* ((machine (make-chip8-machine :platform :schip))
           (app (make-chip8-app
                 :machine machine
                 :state-machine (cl-chip8::make-chip8-control-state-machine)
                 :clock-hz 60)))
      (setf (cl-dataflow-kit:state-machine-state
             (chip8-app-state-machine app))
            "running"
            (aref (chip8-machine-memory machine) #x200) #x00
            (aref (chip8-machine-memory machine) #x201) #xfd
            (aref (chip8-machine-memory machine) #x202) #x60
            (aref (chip8-machine-memory machine) #x203) #x01)
      (cl-chip8::step-chip8-app! app)
      (expect (cl-chip8::chip8-machine-halted-p machine) :to-be t)
      (expect (chip8-machine-pc machine) :to-be #x202)
      (expect (chip8-machine-register machine 0) :to-be 0)
      (expect (chip8-app-quit-p app) :to-be t)
      (expect (chip8-app-error app) :to-be nil)
      (expect (chip8-control-state (chip8-app-state-machine app))
              :to-equal "finished")))
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
    (dolist (clock-hz '(1 59 60 700 60000))
      (let* ((app (make-chip8-app :clock-hz clock-hz))
             (tick-counts
               (loop repeat 60
                     collect (cl-chip8::%instructions-per-tick app))))
        (expect (loop for count in tick-counts sum count)
                :to-be
                clock-hz)
        (when (= clock-hz 60000)
          (expect tick-counts
                  :to-equal
                  (make-list 60 :initial-element 1000))))))
  (it
    "executes 60,000 instructions over sixty 60,000 Hz app ticks"
    (let* ((machine (make-chip8-machine))
           (app (make-chip8-app :machine machine :clock-hz 60000))
           (*standard-input* (make-string-input-stream "")))
      (load-rom machine #(#x12 #x00))
      (loop repeat 60 do
        (let ((instructions-before (chip8-machine-instructions machine)))
          (cl-chip8::%advance-chip8! app)
          (expect (- (chip8-machine-instructions machine)
                     instructions-before)
                  :to-be
                  1000)))
      (expect (chip8-machine-instructions machine) :to-be 60000)))
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
(describe "P1 machine integration"
  (it "keeps lores pixels visible through the serial app renderer"
    (let* ((machine (make-chip8-machine))
           (renderer (cl-tty-kit:make-renderer +screen-width+ +screen-height+))
           (app (make-chip8-app
                 :machine machine
                 :renderer renderer
                 :render-state (cl-chip8::make-chip8-render-state))))
      (setf (aref (chip8-machine-framebuffer machine) 0 0) 1)
      (cl-chip8::%render-chip8-app! app)
      (expect
        (cl-tty-kit:cell-char
         (cl-tty-kit:screen-cell
          (cl-tty-kit:renderer-screen renderer)
          cl-chip8::+playfield-origin-x+
          cl-chip8::+playfield-origin-y+))
        :to-be
        (code-char #x2580))))
  (it "resumes a 64K key wait through the app input path" (let* ((machine (make-chip8-machine :platform :xo-chip :quirks (make-chip8-quirks :profile :modern :fx0a-completion :press))) (app (make-chip8-app :machine machine :state-machine (make-chip8-control-state-machine) :decoder (cl-tty-kit:make-input-decoder) :clock-hz 60))) (setf (chip8-machine-pc machine) #xfffe) (load-rom machine #(#xf0 #x0a) :address #xfffe) (execute-instruction! machine) (setf (chip8-app-state-machine app) (step-chip8-control-state (step-chip8-control-state (chip8-app-state-machine app) :start) :key-wait)) (expect (chip8-control-state (chip8-app-state-machine app)) :to-equal "waiting-key") (expect (cl-chip8::chip8-wait-state-pc (chip8-machine-waiting machine)) :to-be #xfffe) (cl-chip8::%apply-key-event! app (%app-test-event :character #\3)) (expect (chip8-machine-pc machine) :to-be 0) (expect (chip8-machine-register machine 0) :to-be 3) (expect (chip8-control-state (chip8-app-state-machine app)) :to-equal "running"))))
