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
  (list (coerce (chip8-machine-v machine) 'list)
        (chip8-machine-i machine)
        (chip8-machine-pc machine)
        (coerce (chip8-machine-memory machine) 'list)
        (contract-framebuffer-bits (chip8-framebuffer machine))))

(describe "v0.3.0 shared contracts"
  (it "fixes the deterministic seed and framebuffer shape"
    (let ((framebuffer (make-contract-framebuffer '((0 0) (31 63)))))
      (expect +contract-seed+ :to-be 12345)
      (expect (array-dimensions framebuffer) :to-equal '(32 64))
      (expect (aref framebuffer 0 0) :to-be 1)
      (expect (aref framebuffer 31 63) :to-be 1))))
