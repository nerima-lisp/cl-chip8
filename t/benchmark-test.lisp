(in-package #:cl-chip8/test)

(defun make-benchmark-machine ()
  (let ((machine (make-chip8-machine)))
    (load-rom machine
              (make-array 14 :element-type '(unsigned-byte 8)
                          :initial-contents '(#x60 #x01 #x61 #x02 #xA3 #x00 #xD0 #x11
                                              #x80 #x14 #x70 #x01 #x12 #x00)))
    (setf (aref (chip8-machine-memory machine) #x300) #x80)
    machine))

(defun %benchmark-median (values)
  (let ((sorted (sort (copy-seq values) #'<)))
    (elt sorted (floor (length sorted) 2))))

(describe "headless performance gate"
  (it "keeps median mixed-workload throughput above the host-safe floor"
    (let* ((instructions 100000)
           (milliseconds (%benchmark-median
                          (loop repeat 7
                                collect (minimum-ms
                                         (benchmark (:warmup 1 :samples 1)
                                           (chip8-run-instructions
                                            (make-benchmark-machine) instructions))))))
           (instructions-per-second (/ (* 1000d0 instructions) milliseconds)))
      (expect milliseconds :to-satisfy (lambda (value) (> value 0)))
      ;; Keep the floor low enough for slower hosts; a tenfold slowdown still fails.
      (expect instructions-per-second :to-satisfy (lambda (value) (>= value 1000.0)))
      (format t "~&benchmark: ~,1F instr/s (median sample ~,3F ms)~%"
              instructions-per-second milliseconds))))
