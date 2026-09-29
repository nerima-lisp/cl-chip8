(in-package #:cl-chip8/test)
(defun test-machine () (make-chip8-machine))
(defun test-opcode (machine opcode)
  (load-rom machine (vector (ldb (byte 8 8) opcode) (ldb (byte 8 0) opcode))
            :address (chip8-machine-pc machine))
  (execute-instruction! machine))
(defparameter *opcode-table-cases*
  (loop for profile in '(:modern :cosmac-vip) append
    (loop for opcode in '(#x00e0 #x00ee #x0123 #x1200 #x2200 #x3000 #x4000 #x5000
                          #x6000 #x7000 #x8000 #x8001 #x8002 #x8003 #x8004 #x8005
                          #x8006 #x8007 #x800e #x9000 #xa200 #xb200 #xc0ff #xd010
                          #xe09e #xe0a1 #xf007 #xf00a #xf015 #xf018 #xf01e #xf029
                          #xf033 #xf055 #xf065)
          collect (list profile opcode))))
(describe "typed CHIP-8 machine"
  (it "resets to the documented initial state"
    (let ((m (test-machine)))
      (expect (chip8-machine-pc m) :to-be #x200) (expect (chip8-machine-i m) :to-be 0)
      (expect (chip8-machine-sp m) :to-be 0) (expect (chip8-machine-register m 0) :to-be 0)))
  (it "executes arithmetic and flow instructions"
    (let ((m (test-machine)))
      (test-opcode m #x6010) (test-opcode m #x7001)
      (expect (chip8-machine-register m 0) :to-be #x11)
      (test-opcode m #x1200) (expect (chip8-machine-pc m) :to-be #x200)))
  (it "snapshots framebuffer without aliasing"
    (let ((m (test-machine)))
      (setf (aref (chip8-machine-framebuffer m) 2 3) 1)
      (let ((copy (chip8-framebuffer m))) (setf (aref copy 2 3) 0) (expect (aref (chip8-machine-framebuffer m) 2 3) :to-be 1))))
  (it "signals stack and memory errors"
    (let ((m (test-machine))) (signals chip8-stack-underflow (test-opcode m #x00ee)) (signals chip8-memory-access-out-of-bounds (check-memory-access 4095 2)))))

(it-each ((:modern #x00e0) (:modern #x00ee) (:modern #x0123) (:modern #x1200) (:modern #x2200) (:modern #x3000) (:modern #x4000) (:modern #x5000) (:modern #x6000) (:modern #x7000) (:modern #x8000) (:modern #x8001) (:modern #x8002) (:modern #x8003) (:modern #x8004) (:modern #x8005) (:modern #x8006) (:modern #x8007) (:modern #x800e) (:modern #x9000) (:modern #xa200) (:modern #xb200) (:modern #xc0ff) (:modern #xd010) (:modern #xe09e) (:modern #xe0a1) (:modern #xf007) (:modern #xf00a) (:modern #xf015) (:modern #xf018) (:modern #xf01e) (:modern #xf029) (:modern #xf033) (:modern #xf055) (:modern #xf065) (:cosmac-vip #x00e0) (:cosmac-vip #x00ee) (:cosmac-vip #x0123) (:cosmac-vip #x1200) (:cosmac-vip #x2200) (:cosmac-vip #x3000) (:cosmac-vip #x4000) (:cosmac-vip #x5000) (:cosmac-vip #x6000) (:cosmac-vip #x7000) (:cosmac-vip #x8000) (:cosmac-vip #x8001) (:cosmac-vip #x8002) (:cosmac-vip #x8003) (:cosmac-vip #x8004) (:cosmac-vip #x8005) (:cosmac-vip #x8006) (:cosmac-vip #x8007) (:cosmac-vip #x800e) (:cosmac-vip #x9000) (:cosmac-vip #xa200) (:cosmac-vip #xb200) (:cosmac-vip #xc0ff) (:cosmac-vip #xd010) (:cosmac-vip #xe09e) (:cosmac-vip #xe0a1) (:cosmac-vip #xf007) (:cosmac-vip #xf00a) (:cosmac-vip #xf015) (:cosmac-vip #xf018) (:cosmac-vip #xf01e) (:cosmac-vip #xf029) (:cosmac-vip #xf033) (:cosmac-vip #xf055) (:cosmac-vip #xf065)) "executes opcode table case ~A ~4,'0X" (profile opcode)
  (let ((m (make-chip8-machine :quirks (make-chip8-quirks :profile profile))))
    (setf (chip8-machine-sp m) 1 (aref (chip8-machine-stack m) 0) #x200)
    (handler-case (test-opcode m opcode)
      (chip8-error () nil))
    (expect (chip8-machine-instructions m) :to-be 1)))
