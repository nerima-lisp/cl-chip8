(in-package #:cl-chip8/test)

(defun make-benchmark-machine ()
  (let ((machine (make-chip8-machine)))
    (load-rom machine
              (make-array 14 :element-type '(unsigned-byte 8)
                          :initial-contents '(#x60 #x01 #x61 #x02 #xA3 #x00 #xD0 #x11
                                              #x80 #x14 #x70 #x01 #x12 #x00)))
    (setf (aref (chip8-machine-memory machine) #x300) #x80)
    machine))

(describe "headless performance gate"
  (it "executes mixed ALU, draw, and branch workload at 7000 instr/s or faster"
    (let* ((instructions 100000)
           (result (benchmark (:warmup 1 :samples 3)
                     (chip8-run-instructions (make-benchmark-machine) instructions)))
           (milliseconds (minimum-ms result))
           (instructions-per-second (/ (* 1000d0 instructions) milliseconds)))
      (expect milliseconds :to-satisfy (lambda (value) (> value 0)))
      (expect instructions-per-second :to-satisfy (lambda (value) (>= value 7000.0)))
      (format t "~&benchmark: ~,1F instr/s (minimum sample ~,3F ms)~%"
              instructions-per-second milliseconds))))
