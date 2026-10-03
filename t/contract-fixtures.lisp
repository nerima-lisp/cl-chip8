(in-package #:cl-chip8/test)

(defconstant +contract-seed+ 12345)
(defconstant +contract-framebuffer-height+ 32)
(defconstant +contract-framebuffer-width+ 64)
(defconstant +contract-benchmark-runs+ 5)
(defconstant +contract-benchmark-instructions+ 100000)
(defconstant +contract-min-throughput+ 100000.0d0)

(defun make-contract-framebuffer (&optional (pixels '()))
  (let ((framebuffer
          (make-array (list +contract-framebuffer-height+
                            +contract-framebuffer-width+)
                      :element-type 'bit
                      :initial-element 0)))
    (dolist (pixel pixels framebuffer)
      (destructuring-bind (y x) pixel
        (setf (aref framebuffer y x) 1)))))

(defun contract-framebuffer-bits (framebuffer)
  (loop for index below (array-total-size framebuffer)
        collect (row-major-aref framebuffer index)))

(defun contract-machine-signature (machine)
  (list :registers (coerce (chip8-machine-v machine) 'list)
        :i (chip8-machine-i machine)
        :pc (chip8-machine-pc machine)
        :memory (coerce (chip8-machine-memory machine) 'list)
        :framebuffer (contract-framebuffer-bits (chip8-framebuffer machine))))

(defun contract-random-signature (&optional seed-p seed)
  (let ((machine (if seed-p
                    (make-chip8-machine :seed seed)
                    (make-chip8-machine))))
    (load-rom machine #(#xC0 #xFF #xC1 #xFF #xC2 #xFF #xC3 #xFF))
    (chip8-run-instructions machine 4)
    (list :seed (chip8-machine-seed machine)
          :state (contract-machine-signature machine))))

(describe "v0.3.0 shared contracts"
  (it "fixes the deterministic seed and framebuffer shape"
    (let ((framebuffer (make-contract-framebuffer '((0 0) (31 63)))))
      (expect +contract-seed+ :to-be 12345)
      (expect (array-dimensions framebuffer) :to-equal '(32 64))
      (expect (aref framebuffer 0 0) :to-be 1)
      (expect (aref framebuffer 31 63) :to-be 1)))
  (it "makes default and explicit seeds deterministic"
    (let ((default-a (contract-random-signature))
          (default-b (contract-random-signature))
          (explicit-zero (contract-random-signature t 0))
          (seed-a (contract-random-signature t +contract-seed+))
          (seed-b (contract-random-signature t +contract-seed+))
          (different-seed (contract-random-signature t (1+ +contract-seed+))))
      (expect default-a :to-equal default-b)
      (expect default-a :to-equal explicit-zero)
      (expect seed-a :to-equal seed-b)
      (expect seed-a :not :to-equal different-seed)
      (expect (getf (getf seed-a :state) :registers) :to-equal
              (getf (getf seed-b :state) :registers))
      (expect (getf (getf seed-a :state) :framebuffer) :to-equal
              (getf (getf seed-b :state) :framebuffer))))
  (it "restarts the seeded random stream on reset"
    (let ((machine (make-chip8-machine :seed +contract-seed+)))
      (load-rom machine #(#xC0 #xFF #xC1 #xFF))
      (chip8-run-instructions machine 2)
      (let ((first-run (contract-machine-signature machine)))
        (chip8-reset! machine)
        (load-rom machine #(#xC0 #xFF #xC1 #xFF))
        (chip8-run-instructions machine 2)
        (expect first-run :to-equal (contract-machine-signature machine)))))
  (it "rejects seeds outside the unsigned 32-bit contract"
    (signals type-error (make-chip8-machine :seed -1)))
  (it "keeps the zero RNG state within the byte contract"
    (let ((machine (make-chip8-machine)))
      (setf (cl-chip8::chip8-machine-rng-state machine) 0)
      (expect (cl-chip8::chip8-random-byte machine) :to-be 0)
      (expect (cl-chip8::chip8-machine-rng-state machine) :to-be 0))))
