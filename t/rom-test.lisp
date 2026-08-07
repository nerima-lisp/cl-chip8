;;;; t/rom-test.lisp -- READ-FILE-BYTES and LOAD-ROM-FILE!, including the
;;;; too-large condition case.
(in-package #:cl-chip8/test)

(defun %call-with-temp-rom-file (bytes thunk)
  "Write BYTES to a fresh file under /tmp, call THUNK with its pathname, and
delete it afterwards. This target is SBCL-only (see the org's PACKAGE_STANDARD
and cl-chip8.asd), so a plain /tmp path avoids depending on any particular
   external temporary-file API surface."
  (let ((path (merge-pathnames
               (format nil "cl-chip8-rom-test-~D-~D.ch8" (get-universal-time) (random 1000000))
               #p"/tmp/")))
    (unwind-protect
         (progn
           (with-open-file (stream path :direction :output :if-exists :supersede
                                   :element-type '(unsigned-byte 8))
             (write-sequence bytes stream))
           (funcall thunk path))
      (when (probe-file path) (delete-file path)))))

(defmacro with-temp-rom-file ((path-var bytes) &body body)
  `(%call-with-temp-rom-file ,bytes (lambda (,path-var) ,@body)))

(describe "read-file-bytes"
  (it "reads the exact bytes written to the file"
    (with-temp-rom-file (path #(1 2 3 4))
      (expect (coerce (read-file-bytes path) 'list) :to-equal '(1 2 3 4)))))

(describe "load-rom-file!"
  (it "loads the file's bytes into memory at +rom-load-address+"
    (memory-reset!)
    (with-temp-rom-file (path #(10 20 30))
      (load-rom-file! path)
      (with-soft-assertions
        (expect (aref *memory* +rom-load-address+) :to-be 10)
        (expect (aref *memory* (+ +rom-load-address+ 1)) :to-be 20)
        (expect (aref *memory* (+ +rom-load-address+ 2)) :to-be 30))))
  (it "signals chip8-rom-too-large for a ROM that does not fit"
    (memory-reset!)
    (with-temp-rom-file (path (make-array (1+ (- +memory-size+ +rom-load-address+))
                                          :element-type '(unsigned-byte 8) :initial-element 0))
      (signals chip8-rom-too-large
        (load-rom-file! path))))
  (it "signals chip8-rom-too-large via read-file-bytes' own :max-size argument"
    (with-temp-rom-file (path #(1 2 3 4 5))
      (signals chip8-rom-too-large
        (read-file-bytes path :max-size 4)))))

(describe "regular-file-p and check-regular-rom-file (security review: non-regular ROM paths)"
  (it "returns false for a path that does not exist"
    (expect (regular-file-p #p"/tmp/cl-chip8-rom-test-does-not-exist-9999.ch8") :to-be-falsy))
  (it "does not signal for a path that does not exist -- left to read-file-bytes' own file-error"
    (expect (check-regular-rom-file #p"/tmp/cl-chip8-rom-test-does-not-exist-9999.ch8")
            :to-be-falsy))
  (it "returns true for an ordinary regular file"
    (with-temp-rom-file (path #(1 2 3))
      (expect (regular-file-p path) :to-be-truthy)))
  (it "signals chip8-rom-not-regular-file for a directory"
    (signals chip8-rom-not-regular-file (check-regular-rom-file #p"/tmp/")))
  (it "signals chip8-rom-not-regular-file for a FIFO, without blocking on it"
    ;; The whole point of this check (see rom.lisp) is that FILE-LENGTH/READ-
    ;; SEQUENCE on a FIFO can block forever; this proves LOAD-ROM-FILE! never
    ;; reaches that call for one.
    (let ((path (merge-pathnames
                 (format nil "cl-chip8-rom-test-fifo-~D-~D" (get-universal-time) (random 1000000))
                 #p"/tmp/")))
      (unwind-protect
           (progn
             (sb-posix:mkfifo (namestring path) #o600)
             (signals chip8-rom-not-regular-file (load-rom-file! path)))
        (when (probe-file path) (delete-file path))))))
