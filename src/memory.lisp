(in-package #:cl-chip8)

(defun memory-reset! (machine)
  (fill (chip8-machine-memory machine) 0)
  (load-fontset-into-memory! machine)
  machine)

(defun check-memory-access (machine address span)
  (let ((capacity (chip8-machine-memory-size machine)))
    (unless (and (typep address '(integer 0 *))
                 (typep span '(integer 0 *))
                 (<= (+ address span) capacity))
      (error 'chip8-memory-access-out-of-bounds
             :address address
             :span span)))
  t)

(defun load-bytes-into-memory (machine bytes &optional (address +rom-load-address+))
  (unless (typep address '(integer 0 *))
    (error 'chip8-memory-access-out-of-bounds :address address :span (length bytes)))
  (let ((capacity (chip8-machine-memory-size machine)))
    (unless (<= address capacity)
      (error 'chip8-memory-access-out-of-bounds :address address :span (length bytes)))
    (let ((available (- capacity address)))
      (unless (<= (length bytes) available)
        (error 'chip8-rom-too-large :size (length bytes) :available available))
      (replace (chip8-machine-memory machine) bytes :start1 address)))
  machine)

(defun memory-read (machine address)
  (check-memory-access machine address 1)
  (aref (chip8-machine-memory machine) address))

(defun (setf memory-read) (value machine address)
  (check-memory-access machine address 1)
  (setf (aref (chip8-machine-memory machine) address)
        (ldb (byte 8 0) value)))
