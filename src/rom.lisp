;;;; src/rom.lisp -- reading a ROM file from disk into *MEMORY*.
(in-package #:cl-chip8)

(defun regular-file-p (path)
  "True when PATH names a regular file."
  (and (probe-file path)
       (sb-posix:s-isreg (sb-posix:stat-mode (sb-posix:stat (namestring path))))))

(defun check-regular-rom-file (path)
  "Signal CHIP8-ROM-NOT-REGULAR-FILE for an existing non-regular PATH."
  (when (and (probe-file path) (not (regular-file-p path)))
    (error 'chip8-rom-not-regular-file :path path))
  (values))

(defun %read-file-bytes-from-stream (stream size)
  "Read SIZE bytes from STREAM into a fresh unsigned-byte vector.

READ-SEQUENCE is allowed to return before the requested end position, so a
single call is not enough to establish that a file was read completely. Keep
reading after a short read and signal CHIP8-ROM-SHORT-READ if EOF arrives
before SIZE bytes are available."
  (let ((bytes (make-array size :element-type '(unsigned-byte 8))))
    (loop with position = 0
          while (< position size)
          for next-position = (read-sequence bytes stream :start position)
          do (if (<= next-position position)
                 (error 'chip8-rom-short-read
                        :actual-size position
                        :expected-size size)
                 (setf position next-position)))
    bytes))

(defun read-file-bytes (path &key max-size)
  "Return PATH's bytes, enforcing MAX-SIZE when supplied."
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((size (file-length stream)))
      (when (and max-size (> size max-size))
        (error 'chip8-rom-too-large :size size :available max-size))
      (%read-file-bytes-from-stream stream size))))

(defun load-rom-file! (path)
  "Read PATH and load it at +ROM-LOAD-ADDRESS+."
  (check-regular-rom-file path)
  (load-bytes-into-memory
   (read-file-bytes path :max-size (- +memory-size+ +rom-load-address+))
   +rom-load-address+))
