(in-package #:cl-chip8)
(defvar *rom-database-records* nil)
(defun find-rom-record (rom-or-sha1)
  (let ((sha1
          (typecase rom-or-sha1
            (string
             (when (and (= (length rom-or-sha1) 40)
                        (every
                         (function
                          (lambda (character)
                            (or (char<= #\0 character #\9)
                                (char<= #\a character #\f)
                                (char<= #\A character #\F))))
                         rom-or-sha1))
               (string-downcase rom-or-sha1)))
            ((vector (unsigned-byte 8))
             (let ((digest (crypto-kit:digest :sha1 rom-or-sha1)))
               (with-output-to-string (stream)
                 (loop for octet across digest
                       do (write-char
                           (char-downcase
                            (digit-char (ldb (byte 4 4) octet) 16))
                           stream)
                          (write-char
                           (char-downcase
                            (digit-char (ldb (byte 4 0) octet) 16))
                           stream))))))))
    (when sha1
      (loop for record in *rom-database-records*
            when (string= sha1 (car record))
              return (cdr record)))))
