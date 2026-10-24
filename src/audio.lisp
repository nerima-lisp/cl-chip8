(in-package #:cl-chip8)

(defconstant +audio-sample-rate+
  48000d0)

(defconstant +audio-pattern-bit-count+
  128d0)

(defparameter +default-audio-pattern+
  (make-array 16 :element-type '(unsigned-byte 8) :initial-element #x0f))

(defun synthesize-audio-frames (frame-count sound-timer pattern pitch bit-phase)
  "Return 48 kHz mono single-float frames and the next pattern-bit phase.
Pattern is a 16-byte unsigned-byte vector read most-significant bit first.
Pitch sets the bit rate to 4000 * 2^((pitch - 64) / 48) bits per second.
Set bits yield 0.25; unset bits yield -0.25.
A positive sound timer enables synthesis for the requested frame count;
otherwise, return silence and reset the phase."
  (declare (type (integer 0 *) frame-count)
           (type integer sound-timer)
           (type (simple-array (unsigned-byte 8) (16)) pattern)
           (type (unsigned-byte 8) pitch)
           (type real bit-phase))
  (if (not (plusp sound-timer))
      (values (make-array frame-count
                          :element-type 'single-float
                          :initial-element 0.0f0)
              0d0)
      (let* ((samples (make-array frame-count :element-type 'single-float))
             (phase (mod (coerce bit-phase 'double-float)
                         +audio-pattern-bit-count+))
             (bit-step (/ (* 4000d0
                             (expt 2d0 (/ (- pitch 64) 48d0)))
                          +audio-sample-rate+)))
        (dotimes (frame frame-count)
          (let* ((sample-phase
                   (mod (+ phase (* frame bit-step))
                        +audio-pattern-bit-count+))
                 (pattern-bit (floor sample-phase))
                 (pattern-byte (aref pattern (floor pattern-bit 8)))
                 (bit-offset (- 7 (mod pattern-bit 8))))
            (setf (aref samples frame)
                  (if (logbitp bit-offset pattern-byte)
                      0.25f0
                      -0.25f0))))
        (values samples
                (mod (+ phase (* frame-count bit-step))
                     +audio-pattern-bit-count+)))))
