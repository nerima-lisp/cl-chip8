(in-package #:cl-chip8/test)

(defun %audio-output-test-pattern (value)
  (make-array 16 :element-type '(unsigned-byte 8) :initial-element value))
(defun %load-machine-audio-state (machine pattern pitch)
  (let ((memory (chip8-machine-memory machine)))
    (loop for byte across pattern
          for address from #x300
          do (setf (aref memory address) byte)))
  (setf (chip8-machine-i machine) #x300
        (chip8-machine-register machine 0) 1
        (chip8-machine-register machine 3) pitch)
  (load-rom
   machine
   (make-array 6
               :element-type '(unsigned-byte 8)
               :initial-contents '(#xf0 #x02 #xf3 #x3a #xf0 #x18)))
  (dotimes (index 3)
    (execute-instruction! machine))
  machine)
(defun %wait-for-audio-output-event (output semaphore event)
  (let ((thread (cl-chip8::chip8-audio-output-thread output)))
    (loop repeat 100
          do (when (sb-thread:wait-on-semaphore semaphore :timeout 0.05)
               (return-from %wait-for-audio-output-event t))
             (unless (sb-thread:thread-alive-p thread)
               (error "Audio output worker terminated while waiting for event ~S: ~A"
                      event
                      (or (cl-chip8::chip8-audio-output-failure output)
                          "No worker failure was recorded."))))
    (error "Timed out waiting for event ~S." event)))
(defun %stop-audio-output-test-output! (output stop-state &optional release-semaphore)
  (let ((thread (first stop-state))
        (join-timeout-marker (list :audio-output-stop-timeout)))
    (flet ((release-write-gate ()
             (when (and release-semaphore
                        (not (fourth stop-state)))
               (setf (fourth stop-state) t)
               (sb-thread:signal-semaphore release-semaphore))))
      (unwind-protect
           (progn
             (when (eq (third stop-state) :join-timeout)
               (error "Timed out waiting for event ~S." :audio-output-stop))
             (unless thread
               (setf thread
                     (sb-thread:make-thread
                      (lambda ()
                        (handler-case
                            (cl-chip8::stop-chip8-audio-output! output)
                          (error (condition)
                            (setf (second stop-state) condition))))))
               (setf (first stop-state) thread))
             (unless (or (eq (third stop-state) :request-timeout)
                         (eq (third stop-state) :joined))
               (let ((stop-requested-p nil))
                 (unwind-protect
                      (progn
                        (loop repeat 100
                              do (when
                                     (sb-thread:with-mutex
                                         ((cl-chip8::chip8-audio-output-lock
                                           output)
                                          :wait-p nil)
                                       (cl-chip8::chip8-audio-output-stopped-p
                                        output))
                                   (setf (third stop-state) :stop-requested
                                         stop-requested-p t)
                                   (return))
                                 (unless (sb-thread:thread-alive-p thread)
                                   (when (eq
                                          (sb-thread:join-thread
                                           thread
                                           :timeout 5
                                           :default join-timeout-marker)
                                          join-timeout-marker)
                                     (setf (third stop-state) :join-timeout)
                                     (error "Timed out waiting for event ~S."
                                            :audio-output-stop))
                                   (setf (third stop-state) :joined)
                                   (when (second stop-state)
                                     (error (second stop-state)))
                                   (error
                                    "Audio output stop worker terminated while waiting for event ~S."
                                    :audio-output-stop-request))
                                 (sleep 0.05))
                        (unless stop-requested-p
                          (setf (third stop-state) :request-timeout)
                          (error "Timed out waiting for event ~S."
                                 :audio-output-stop-request)))
                   (release-write-gate))))
             (release-write-gate)
             (unless (eq (third stop-state) :joined)
               (setf (third stop-state) :joining)
               (when (eq (sb-thread:join-thread
                          thread
                          :timeout 5
                          :default join-timeout-marker)
                         join-timeout-marker)
                 (setf (third stop-state) :join-timeout)
                 (error "Timed out waiting for event ~S." :audio-output-stop))
               (setf (third stop-state) :joined))
             (when (second stop-state)
               (error (second stop-state)))
             output)
        (release-write-gate)))))

(describe "audio mode resolution"
  (it "falls back from auto to bell once when opening the device fails"
    (let ((fallback-count 0))
      (multiple-value-bind (mode stream)
          (cl-chip8::%resolve-chip8-audio-mode
           :auto
           :open-stream
           (lambda (&rest arguments)
             (declare (ignore arguments))
             (error 'cl-audio-kit:audio-error :operation "open"))
           :on-fallback
           (lambda (condition)
             (declare (ignore condition))
             (incf fallback-count)))
        (expect mode :to-be :bell)
        (expect stream :to-be nil)
        (expect fallback-count :to-be 1))))

  (it "propagates forced PCM open failures without falling back"
    (let ((fallback-count 0))
      (expect
       (signals cl-audio-kit:audio-error
         (cl-chip8::%resolve-chip8-audio-mode
          :pcm
          :open-stream
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (error 'cl-audio-kit:audio-error :operation "open"))
          :on-fallback
          (lambda (condition)
            (declare (ignore condition))
            (incf fallback-count))))
       :to-be-truthy)
      (expect fallback-count :to-be 0)))

  (it "does not open a device for bell or off mode"
    (let ((open-count 0))
      (dolist (mode '(:bell :off))
        (multiple-value-bind (resolved stream)
            (cl-chip8::%resolve-chip8-audio-mode
             mode
             :open-stream
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (incf open-count)))
          (expect resolved :to-be mode)
          (expect stream :to-be nil)))
      (expect open-count :to-be 0))))

(describe "audio output worker"
  (it "writes a PCM block and joins before closing its stream"
    (let* ((device (cl-audio-kit:make-recording-device))
           (stream (cl-audio-kit:open-output-stream :device device))
           (machine (make-chip8-machine :platform :xo-chip))
           (write-started (sb-thread:make-semaphore))
           (allow-write (sb-thread:make-semaphore))
           (write-finished (sb-thread:make-semaphore))
           (write-outcome nil)
           (output nil)
           (stop-state (list nil nil nil nil))
           (stopped-p nil))
      (setf (chip8-machine-sound-timer machine) 1)
      (fill (chip8-machine-audio-pattern machine) #xff)
      (setf output
            (cl-chip8::start-chip8-audio-output
             stream machine
             :writer
             (lambda (stream samples)
               (sb-thread:signal-semaphore write-started)
               (unwind-protect
                    (handler-case
                        (progn
                          (unless (sb-thread:wait-on-semaphore
                                   allow-write
                                   :timeout 5)
                            (error "Timed out waiting for event ~S."
                                   :allow-write))
                          (prog1 (cl-audio-kit:write-frames stream samples)
                            (setf write-outcome :success)))
                      (error (condition)
                        (setf write-outcome condition)
                        (error condition)))
                 (sb-thread:signal-semaphore write-finished)))))
      (unwind-protect
           (progn
             (%wait-for-audio-output-event output write-started :write-started)
             (%stop-audio-output-test-output! output stop-state allow-write)
             (%wait-for-audio-output-event output write-finished :write-finished)
             (expect write-outcome :to-be :success)
             (setf stopped-p t)
             (multiple-value-bind (frames latency)
                 (cl-chip8::chip8-audio-output-stats output)
               (expect frames :to-be 480)
               (expect latency :to-be 0d0))
             (let ((chunks (cl-audio-kit:recorded-samples device)))
               (expect (length chunks) :to-be 1)
               (let ((samples (first chunks)))
                 (expect (length samples) :to-be 480)
                 (expect (every (lambda (sample) (= sample 0.25f0)) samples)
                         :to-be-truthy)
                 (expect
                  (signals cl-audio-kit:audio-error
                    (cl-audio-kit:write-frames stream samples))
                  :to-be-truthy))))
        (unless stopped-p
          (%stop-audio-output-test-output! output stop-state allow-write)))))
  (it "continues app shutdown when a stalled audio write survives abort"
      (let* ((device (cl-audio-kit:make-recording-device))
             (stream (cl-audio-kit:open-output-stream :device device))
             (machine (make-chip8-machine :platform :xo-chip))
             (write-started (sb-thread:make-semaphore))
             (allow-write (sb-thread:make-semaphore))
             (write-finished (sb-thread:make-semaphore))
             (warning-count 0)
             (abort-count 0)
             (output nil)
             (app nil)
             (stop-state (list nil nil nil nil))
             (stop-elapsed nil)
             (write-released-p nil)
             (test-complete-p nil))
        (setf (chip8-machine-sound-timer machine) 1
              output
              (cl-chip8::start-chip8-audio-output
               stream machine
               :writer
               (lambda (stream samples)
                 (declare (ignore stream samples))
                 (sb-thread:signal-semaphore write-started)
                 (unwind-protect
                     (progn
                       (sb-thread:wait-on-semaphore allow-write)
                       cl-chip8::+audio-frames-per-write+)
                   (sb-thread:signal-semaphore write-finished)))
               :abort-stream-function
               (lambda (stream)
                 (declare (ignore stream))
                 (incf abort-count))
               :on-stop-timeout
               (lambda () (incf warning-count)))
              app
              (make-chip8-app :machine machine
                              :audio-mode :pcm
                              :audio-output output))
        (setf (chip8-app-quit-p app) t)
        (unwind-protect
            (progn
              (%wait-for-audio-output-event output write-started :write-started)
              (let ((started-at (get-internal-real-time)))
                (%stop-audio-output-test-output! output stop-state)
                (setf stop-elapsed
                      (/ (- (get-internal-real-time) started-at)
                         internal-time-units-per-second)))
              (expect (< stop-elapsed 4) :to-be-truthy)
              (expect warning-count :to-be 1)
              (expect abort-count :to-be 1)
              (expect (sb-thread:thread-alive-p
                       (cl-chip8::chip8-audio-output-thread output))
                      :to-be-truthy)
              (expect (cl-chip8::chip8-audio-output-stop-condition output)
                      :to-be-truthy)
              (expect (chip8-app-quit-p app) :to-be-truthy)
              (expect (chip8-app-error app) :to-be nil)
              (expect (signals cl-audio-kit:audio-error
                               (cl-audio-kit:write-frames
                                stream
                                (make-array 0 :element-type 'single-float)))
                      :to-be-truthy)
              (setf test-complete-p t))
          (unless write-released-p
            (setf write-released-p t)
            (sb-thread:signal-semaphore allow-write))
          (%wait-for-audio-output-event output write-finished :write-finished)
          (let* ((thread (cl-chip8::chip8-audio-output-thread output)) (timeout-marker (list :timed-out))) (expect (eq (sb-thread:join-thread thread :timeout 5 :default timeout-marker) timeout-marker) :to-be nil) (expect (sb-thread:thread-alive-p thread) :to-be nil))
          (unless test-complete-p
            (%stop-audio-output-test-output! output stop-state allow-write)))))

  (it "records a worker write failure for the application"
    (let* ((machine (make-chip8-machine))
           (device (cl-audio-kit:make-recording-device))
           (stream (cl-audio-kit:open-output-stream :device device))
           (join-timeout (list :worker-termination-timeout))
           (stop-state (list nil nil nil nil))
           (output nil))
      (setf (chip8-machine-sound-timer machine) 1
            output
            (cl-chip8::start-chip8-audio-output
             stream machine
             :writer
             (lambda (stream samples)
               (declare (ignore stream samples))
               (error 'cl-audio-kit:audio-error :operation "write"))))
      (unwind-protect
           (progn
             (when (eq (sb-thread:join-thread
                        (cl-chip8::chip8-audio-output-thread output)
                        :timeout 5
                        :default join-timeout)
                       join-timeout)
               (error "Timed out waiting for event ~S."
                      :worker-termination))
             (expect (typep (cl-chip8::chip8-audio-output-failure output)
                            'cl-audio-kit:audio-error)
                     :to-be-truthy))
        (%stop-audio-output-test-output! output stop-state))))
  (it "synthesizes XO audio from F002 pattern and FX3A pitch"
    (let* ((machine (make-chip8-machine :platform :xo-chip))
           (pattern (%audio-output-test-pattern 0)))
      (setf (aref pattern 0) #x80)
      (%load-machine-audio-state machine pattern 112)
      (expect (equalp (chip8-machine-audio-pattern machine) pattern)
              :to-be-truthy)
      (expect (chip8-machine-pitch machine) :to-be 112)
      (multiple-value-bind (samples next-phase)
          (cl-chip8::%synthesize-machine-audio-frames machine 12 0d0)
        (expect (every (lambda (sample) (= sample 0.25f0))
                       (subseq samples 0 6))
                :to-be-truthy)
        (expect (every (lambda (sample) (= sample -0.25f0))
                       (subseq samples 6 12))
                :to-be-truthy)
        (expect next-phase :to-be 2d0))))
  (it-each ((:modern) (:schip))
    "keeps the default square wave on ~A without XO audio instructions"
    (platform)
  (let ((machine (make-chip8-machine :platform platform)))
    (setf (chip8-machine-sound-timer machine) 1)
    (multiple-value-bind (expected expected-phase)
        (cl-chip8::synthesize-audio-frames
         192 1 cl-chip8::+default-audio-pattern+ 64 0d0)
      (multiple-value-bind (samples phase)
          (cl-chip8::%synthesize-machine-audio-frames machine 192 0d0)
        (expect (equalp samples expected) :to-be-truthy)
        (expect phase :to-be expected-phase)
        (expect (cl-chip8::chip8-machine-xo-audio-instructions-used-p machine)
                :to-be nil)))))
  (it "uses FX3A pitch to select machine audio on a default modern machine"
    (let* ((machine (make-chip8-machine :platform :modern))
           (pattern (%audio-output-test-pattern 0)))
      (setf (aref pattern 0) #x80)
      (replace (chip8-machine-audio-pattern machine) pattern)
      (setf (chip8-machine-register machine 3) 112)
      (load-rom machine
                (make-array 2
                            :element-type '(unsigned-byte 8)
                            :initial-contents '(#xf3 #x3a)))
      (execute-instruction! machine)
      (setf (chip8-machine-sound-timer machine) 1)
      (expect (cl-chip8::chip8-machine-xo-audio-instructions-used-p machine)
              :to-be-truthy)
      (expect (chip8-machine-pitch machine) :to-be 112)
      (multiple-value-bind (samples next-phase)
          (cl-chip8::%synthesize-machine-audio-frames machine 12 0d0)
        (expect (every (lambda (sample) (= sample 0.25f0))
                       (subseq samples 0 6))
                :to-be-truthy)
        (expect (every (lambda (sample) (= sample -0.25f0))
                       (subseq samples 6 12))
                :to-be-truthy)
        (expect next-phase :to-be 2d0))))
  (it "uses the F002 audio pattern on a default modern machine"
    (let* ((machine (make-chip8-machine :platform :modern))
           (pattern (%audio-output-test-pattern 0)))
      (setf (aref pattern 0) #x80)
      (loop for byte across pattern
            for address from #x300
            do (setf (aref (chip8-machine-memory machine) address) byte))
      (setf (chip8-machine-i machine) #x300)
      (load-rom machine
                (make-array 2
                            :element-type '(unsigned-byte 8)
                            :initial-contents '(#xf0 #x02)))
      (execute-instruction! machine)
      (setf (chip8-machine-sound-timer machine) 1)
      (expect (equalp (chip8-machine-audio-pattern machine) pattern)
              :to-be-truthy)
      (expect (cl-chip8::chip8-machine-xo-audio-instructions-used-p machine)
              :to-be-truthy)
      (multiple-value-bind (samples next-phase)
          (cl-chip8::%synthesize-machine-audio-frames machine 13 0d0)
        (expect (every (lambda (sample) (= sample 0.25f0))
                       (subseq samples 0 12))
                :to-be-truthy)
        (expect (aref samples 12) :to-be -0.25f0)
        (expect next-phase :to-be (+ 1d0 (/ 1d0 12d0)))))))

(describe "application audio integration"
  (it "rings once when the sound timer activates in bell mode"
    (let* ((machine (make-chip8-machine))
           (stream (make-string-output-stream))
           (app (make-chip8-app :machine machine :audio-mode :bell :stream stream)))
      (setf (chip8-machine-sound-timer machine) 1)
      (cl-chip8::%synchronize-chip8-audio-state! app)
      (cl-chip8::%synchronize-chip8-audio-state! app)
      (expect (get-output-stream-string stream)
              :to-equal (string (code-char 7)))))

  (it "does not ring when audio mode is off"
    (let* ((machine (make-chip8-machine))
           (stream (make-string-output-stream))
           (app (make-chip8-app :machine machine :audio-mode :off :stream stream)))
      (setf (chip8-machine-sound-timer machine) 1)
      (cl-chip8::%synchronize-chip8-audio-state! app)
      (expect (get-output-stream-string stream) :to-equal "")))

  (it "resets PCM phase when the sound timer expires before an opcode runs"
    (let* ((machine (make-chip8-machine))
           (output (cl-chip8::%make-chip8-audio-output))
           (app (make-chip8-app :machine machine
                                :state-machine (make-chip8-control-state-machine)
                                :audio-output output
                                :clock-hz 60)))
      (setf (chip8-machine-sound-timer machine) 1
            (aref (chip8-machine-memory machine) #x200) #x00
            (aref (chip8-machine-memory machine) #x201) #xe0)
      (cl-chip8::step-chip8-app! app)
      (expect (chip8-machine-sound-timer machine) :to-be 0)
      (expect (cl-chip8::chip8-audio-output-phase-reset-generation output)
              :to-be 1)))

  (it "reports an asynchronous output failure through the app"
    (let* ((machine (make-chip8-machine))
           (output (cl-chip8::%make-chip8-audio-output))
           (failure (make-condition 'simple-error
                                    :format-control "audio write failed"
                                    :format-arguments nil))
           (app (make-chip8-app :machine machine
                                :audio-output output
                                :audio-mode :pcm)))
      (setf (cl-chip8::chip8-audio-output-worker-condition output) failure)
      (cl-chip8::%synchronize-chip8-audio-state! app)
      (expect (chip8-app-error app) :to-be failure)
      (expect (chip8-app-quit-p app) :to-be-truthy))))
