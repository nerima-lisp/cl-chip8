(in-package #:cl-chip8/test)
(describe "ROM loading"
  (it "loads bytes at the program address"
    (let ((m (make-chip8-machine)))
      (load-rom m #(1 2 3))
      (expect (memory-read m +rom-load-address+) :to-be 1)
      (expect (memory-read m (+ +rom-load-address+ 2)) :to-be 3)))
  (it "rejects an oversized ROM"
    (let ((m (make-chip8-machine)))
      (signals chip8-rom-too-large
        (load-rom m (make-array 3585 :element-type '(unsigned-byte 8))))))
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
