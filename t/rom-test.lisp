(in-package #:cl-chip8/test)
(describe "ROM loading"
  (it "loads bytes at the program address"
    (let ((m (make-chip8-machine)))
      (load-rom m #(1 2 3))
      (expect (memory-read m +rom-load-address+) :to-be 1)
      (expect (memory-read m (+ +rom-load-address+ 2)) :to-be 3)))
  (it "accepts a ROM that fills the default 4K program area"
    (let* ((rom (make-array (- 4096 #x200)
                            :element-type '(unsigned-byte 8)
                            :initial-element #xa5))
           (m (make-chip8-machine)))
      (load-rom m rom)
      (expect (memory-read m #xfff) :to-be #xa5)))
  (it "rejects a ROM larger than the default 4K program area"
    (let ((m (make-chip8-machine)))
      (signals chip8-rom-too-large
        (load-rom m (make-array (1+ (- 4096 #x200))
                                :element-type '(unsigned-byte 8))))))
  (it "accepts exactly 65536 minus 0x200 bytes on XO-CHIP"
    (let* ((rom (make-array (- 65536 #x200)
                            :element-type '(unsigned-byte 8)
                            :initial-element #x5a))
           (m (make-chip8-machine :platform :xo-chip)))
      (load-rom m rom)
      (expect (memory-read m #xffff) :to-be #x5a)))
  (it "rejects an XO-CHIP ROM one byte beyond its memory limit"
    (let ((m (make-chip8-machine :platform :xo-chip)))
      (signals chip8-rom-too-large
        (load-rom m (make-array (1+ (- 65536 #x200))
                                :element-type '(unsigned-byte 8))))))
  (it "loads a full-size ROM when a modern machine's memory is overridden"
    (let* ((rom (make-array (- 65536 #x200)
                            :element-type '(unsigned-byte 8)
                            :initial-element #x3c))
           (m (make-chip8-machine :platform :modern :memory-size 65536)))
      (load-rom m rom)
      (expect (memory-read m #xffff) :to-be #x3c)))
  (it "rejects an empty ROM vector"
    (signals cl-chip8::chip8-rom-empty
      (load-rom (make-chip8-machine)
                (make-array 0 :element-type '(unsigned-byte 8)))))
  (it "rejects an empty ROM file"
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-empty-rom-~D.ch8" (random 1000000))
                 #p"/tmp/")))
      (unwind-protect
           (progn
             (with-open-file (stream path :direction :output :if-exists :supersede
                                     :element-type '(unsigned-byte 8)))
             (signals cl-chip8::chip8-rom-empty
               (load-rom-file (make-chip8-machine) path)))
        (when (probe-file path)
          (delete-file path))))))

(describe "ROM file size limits"
  (it "accepts a 65024-byte ROM file"
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-size-limit-~D.ch8" (random 1000000))
                 #p"/tmp/")))
      (unwind-protect
           (progn
             (with-open-file (stream path :direction :output :if-exists :supersede
                                     :element-type '(unsigned-byte 8))
               (write-sequence (make-array 65024 :element-type '(unsigned-byte 8)
                                                   :initial-element 0)
                               stream))
             (expect (length (cl-chip8::%read-rom-file path)) :to-be 65024))
        (when (probe-file path)
          (delete-file path)))))
  (it "rejects a 65025-byte ROM file"
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-size-limit-~D.ch8" (random 1000000))
                 #p"/tmp/")))
      (unwind-protect
           (progn
             (with-open-file (stream path :direction :output :if-exists :supersede
                                     :element-type '(unsigned-byte 8))
               (write-sequence (make-array 65025 :element-type '(unsigned-byte 8)
                                                   :initial-element 0)
                               stream))
             (signals chip8-rom-too-large
               (cl-chip8::%read-rom-file path)))
        (when (probe-file path)
          (delete-file path)))))
  (it "rejects an extremely large reported ROM size without a file"
    (signals chip8-rom-too-large
      (cl-chip8::%check-rom-size (expt 2 128)))))
(describe "ROM file open boundaries"
  (it "signals file-error for a missing ROM path"
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-missing-rom-~D-~D.ch8"
                         (get-universal-time) (random 1000000))
                 (uiop:temporary-directory))))
      (signals file-error
        (load-rom-file (make-chip8-machine) path))))
  (it "rejects a directory as a ROM file"
    (signals chip8-rom-not-regular-file
      (cl-chip8::%read-rom-file (uiop:temporary-directory))))
  (it "rejects a FIFO without waiting for a writer"
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-rom-fifo-~D-~D"
                         (get-universal-time) (random 1000000))
                 (uiop:temporary-directory)))
          (created-p nil))
      (unwind-protect
           (progn
             (sb-posix:mkfifo (namestring path) #o600)
             (setf created-p t)
             (sb-sys:with-deadline (:seconds 2)
               (signals chip8-rom-not-regular-file
                 (cl-chip8::%read-rom-file path))))
        (when created-p
          (delete-file path))))))
