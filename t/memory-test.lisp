(in-package #:cl-chip8/test)
(describe "machine memory"
  (it "reads and writes bytes"
    (let ((m (make-chip8-machine)))
      (setf (memory-read m 100) 42)
      (expect (memory-read m 100) :to-be 42)))
  (it "checks ranges before access"
    (signals chip8-memory-access-out-of-bounds (check-memory-access 4095 2))))
