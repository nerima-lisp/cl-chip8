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
           (output nil)
           (stopped-p nil))
      (setf (chip8-machine-sound-timer machine) 1)
      (fill (chip8-machine-audio-pattern machine) #xff)
      (setf output
            (cl-chip8::start-chip8-audio-output
             stream machine
             :writer
             (lambda (stream samples)
               (sb-thread:signal-semaphore write-started)
               (sb-thread:wait-on-semaphore allow-write)
               (cl-audio-kit:write-frames stream samples))))
      (unwind-protect
           (progn
             (sb-thread:wait-on-semaphore write-started)
             (sb-thread:with-mutex ((cl-chip8::chip8-audio-output-lock output))
               (setf (cl-chip8::chip8-audio-output-stopped-p output) t))
             (sb-thread:signal-semaphore allow-write)
             (cl-chip8::stop-chip8-audio-output! output)
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
          (sb-thread:signal-semaphore allow-write)
          (cl-chip8::stop-chip8-audio-output! output)))))

  (it "records a worker write failure for the application"
    (let* ((machine (make-chip8-machine))
           (device (cl-audio-kit:make-recording-device))
           (stream (cl-audio-kit:open-output-stream :device device))
           (output nil))
      (setf (chip8-machine-sound-timer machine) 1
            output
            (cl-chip8::start-chip8-audio-output
             stream machine
             :writer
             (lambda (stream samples)
               (declare (ignore stream samples))
               (error 'cl-audio-kit:audio-error :operation "write"))))
      (sb-thread:join-thread (cl-chip8::chip8-audio-output-thread output))
      (expect (typep (cl-chip8::chip8-audio-output-failure output)
                     'cl-audio-kit:audio-error)
              :to-be-truthy)
      (cl-chip8::stop-chip8-audio-output! output)))
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
  (it "uses the default waveform for non-XO machines after F002 and FX3A"
    (let* ((machine (make-chip8-machine :platform :modern))
           (pattern (%audio-output-test-pattern #xff)))
      (%load-machine-audio-state machine pattern 112)
      (expect (equalp (chip8-machine-audio-pattern machine) pattern)
              :to-be-truthy)
      (expect (chip8-machine-pitch machine) :to-be 112)
      (multiple-value-bind (samples next-phase)
          (cl-chip8::%synthesize-machine-audio-frames machine 192 0d0)
        (expect (every (lambda (sample) (= sample -0.25f0))
                       (subseq samples 0 48))
                :to-be-truthy)
        (expect (every (lambda (sample) (= sample 0.25f0))
                       (subseq samples 48 96))
                :to-be-truthy)
        (expect (every (lambda (sample) (= sample -0.25f0))
                       (subseq samples 96 144))
                :to-be-truthy)
        (expect (every (lambda (sample) (= sample 0.25f0))
                       (subseq samples 144 192))
                :to-be-truthy)
        (expect next-phase :to-be 16d0)))))

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
