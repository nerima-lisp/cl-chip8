(in-package #:cl-chip8)
(defun load-rom (machine bytes &key (address +rom-load-address+))
  (when (zerop (length bytes))
    (error 'chip8-rom-empty))
  (load-bytes-into-memory machine bytes address))

(defun %check-rom-size (size)
  (let ((available (- +maximum-memory-size+ +rom-load-address+)))
    (when (> size available)
      (error 'chip8-rom-too-large :size size :available available))
    size))
(defun %open-rom-stream (pathname missing-error-p)
  (let ((fd
          (handler-case
              (progn
                ;; Open FIFOs without waiting for a writer so fstat can reject them.
                (sb-posix:open pathname
                               (logior sb-posix:o-rdonly sb-posix:o-nonblock)))
            (sb-posix:syscall-error (condition)
              (if (= (sb-posix:syscall-errno condition) sb-posix:enoent)
                  (if missing-error-p
                      (error "ROM file does not exist: ~A" pathname)
                      (error 'file-error :pathname pathname))
                  (error condition)))))
        (stream nil))
    (unwind-protect
         (setf stream
               (sb-sys:make-fd-stream fd :input t
                                      :element-type '(unsigned-byte 8)
                                      :auto-close t))
      (unless stream
        (sb-posix:close fd)))
    stream))
(defun %read-rom-file (pathname &optional missing-error-p)
  (with-open-stream (stream (%open-rom-stream pathname missing-error-p))
    (let ((file-stat (sb-posix:fstat (sb-sys:fd-stream-fd stream))))
      (unless (sb-posix:s-isreg (sb-posix:stat-mode file-stat))
        (error 'chip8-rom-not-regular-file :path pathname))
      (let* ((size (%check-rom-size (sb-posix:stat-size file-stat)))
             (bytes (make-array size :element-type '(unsigned-byte 8))))
        (let ((actual-size (read-sequence bytes stream)))
          (unless (= actual-size size)
            (error 'chip8-rom-short-read
                   :actual-size actual-size
                   :expected-size size)))
        bytes))))
(defun load-rom-file (machine pathname)
  (load-rom machine (%read-rom-file pathname)))
