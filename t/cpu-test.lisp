(in-package #:cl-chip8/test)
(defun test-machine () (make-chip8-machine))
(defun test-opcode (machine opcode)
  (load-rom machine (vector (ldb (byte 8 8) opcode) (ldb (byte 8 0) opcode)))
  (execute-instruction! machine))
(describe "typed CHIP-8 machine"
  (it "resets to the documented initial state"
    (let ((m (test-machine)))
      (expect (chip8-machine-pc m) :to-be #x200) (expect (chip8-machine-i m) :to-be 0)
      (expect (chip8-machine-sp m) :to-be 0) (expect (chip8-machine-register m 0) :to-be 0)))
  (it "executes arithmetic and flow instructions"
    (let ((m (test-machine)))
      (test-opcode m #x6010) (test-opcode m #x7101)
      (expect (chip8-machine-register m 0) :to-be #x11)
      (test-opcode m #x1200) (expect (chip8-machine-pc m) :to-be #x200)))
  (it "snapshots framebuffer without aliasing"
    (let ((m (test-machine)))
      (setf (aref (chip8-machine-framebuffer m) 2 3) 1)
      (let ((copy (chip8-framebuffer m))) (setf (aref copy 2 3) 0) (expect (aref (chip8-machine-framebuffer m) 2 3) :to-be 1))))
  (it "signals stack and memory errors"
    (let ((m (test-machine))) (signals chip8-stack-underflow (test-opcode m #x00ee)) (signals chip8-memory-access-out-of-bounds (check-memory-access 4095 2)))))
