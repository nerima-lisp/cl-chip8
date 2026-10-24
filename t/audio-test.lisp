(in-package #:cl-chip8/test)

(defun %audio-test-pattern (first-byte)
  (let ((pattern
         (make-array 16 :element-type '(unsigned-byte 8) :initial-element 0)))
    (setf (aref pattern 0) first-byte)
    pattern))

(defun %audio-samples-have-value-p (samples start end value)
  (loop for index from start below
        end
        always (= (aref samples index) value)))

(describe "audio synthesis"
  (it-each ((64 12) (112 6))
      "reads pattern bits MSB-first at pitch ~A"
      (pitch frames-per-bit)
    (let ((pattern (%audio-test-pattern #x80)))
      (multiple-value-bind (samples next-phase)
          (cl-chip8::synthesize-audio-frames (* 2 frames-per-bit)
                                             1
                                             pattern
                                             pitch
                                             0d0)
        (expect (%audio-samples-have-value-p samples 0 frames-per-bit 0.25f0)
                :to-be-truthy)
        (expect (%audio-samples-have-value-p samples
                                            frames-per-bit
                                            (* 2 frames-per-bit)
                                            -0.25f0)
                :to-be-truthy)
        (expect (= next-phase 2d0) :to-be-truthy))))

  (it "wraps after 128 pattern bits without changing the pattern"
    (let* ((pattern (%audio-test-pattern #x80))
           (original (copy-seq pattern)))
      (multiple-value-bind (samples next-phase)
          (cl-chip8::synthesize-audio-frames 7 1 pattern 64 127.5d0)
        (expect (%audio-samples-have-value-p samples 0 6 -0.25f0)
                :to-be-truthy)
        (expect (= (aref samples 6) 0.25f0) :to-be-truthy)
        (expect (<= (abs (- next-phase (/ 1d0 12d0))) 1d-12)
                :to-be-truthy)
        (expect (equalp pattern original) :to-be-truthy))))

  (it "continues phase across active timer and pitch changes"
    (let ((pattern (%audio-test-pattern #x80)))
      (multiple-value-bind (first-samples phase)
          (cl-chip8::synthesize-audio-frames 6 3 pattern 64 0d0)
        (expect (%audio-samples-have-value-p first-samples 0 6 0.25f0)
                :to-be-truthy)
        (expect (= phase 0.5d0) :to-be-truthy)
        (multiple-value-bind (second-samples next-phase)
            (cl-chip8::synthesize-audio-frames 3 2 pattern 112 phase)
          (expect (%audio-samples-have-value-p second-samples 0 3 0.25f0)
                  :to-be-truthy)
          (expect (= next-phase 1d0) :to-be-truthy)
          (multiple-value-bind (third-samples final-phase)
              (cl-chip8::synthesize-audio-frames 1 1 pattern 64 next-phase)
            (expect (= (aref third-samples 0) -0.25f0) :to-be-truthy)
            (expect (= final-phase (+ 1d0 (/ 1d0 12d0)))
                    :to-be-truthy))))))

  (it "silences and resets phase when the timer is zero"
    (let ((pattern (%audio-test-pattern #xff)))
      (multiple-value-bind (samples phase)
          (cl-chip8::synthesize-audio-frames 4 0 pattern 64 31.75d0)
        (expect (%audio-samples-have-value-p samples 0 4 0.0f0)
                :to-be-truthy)
        (expect (= phase 0d0) :to-be-truthy)
        (multiple-value-bind (resumed-samples resumed-phase)
            (cl-chip8::synthesize-audio-frames 1 1 pattern 64 phase)
          (expect (= (aref resumed-samples 0) 0.25f0) :to-be-truthy)
          (expect (= resumed-phase (/ 1d0 12d0)) :to-be-truthy)))))

  (it "uses the configured 500 Hz default square wave"
    (let ((pattern cl-chip8::+default-audio-pattern+))
      (multiple-value-bind (samples next-phase)
          (cl-chip8::synthesize-audio-frames 192 1 pattern 64 0d0)
        (expect (and (typep samples '(array single-float (*)))
                     (typep next-phase 'double-float))
                :to-be-truthy)
        (expect (every (lambda (byte) (= byte #x0f)) pattern)
                :to-be-truthy)
        (expect (%audio-samples-have-value-p samples 0 48 -0.25f0)
                :to-be-truthy)
        (expect (%audio-samples-have-value-p samples 48 96 0.25f0)
                :to-be-truthy)
        (expect (%audio-samples-have-value-p samples 96 144 -0.25f0)
                :to-be-truthy)
        (expect (%audio-samples-have-value-p samples 144 192 0.25f0)
                :to-be-truthy)
        (expect (= next-phase 16d0) :to-be-truthy)))))
