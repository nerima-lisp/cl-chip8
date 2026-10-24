(in-package #:cl-chip8/test)
(describe "ROM database"
  (it "finds the preferred CHIP-8 platform and numeric tickrate"
    (let ((record
            (cl-chip8:find-rom-record "d6d8efef811350e7fba6197024c4973b360749b8")))
      (expect (first (getf record :platforms)) :to-be :original-chip8)
      (expect (numberp (getf record :tickrate)) :to-be t)
      (expect
       (cl-chip8:find-rom-record "D6D8EFEF811350E7FBA6197024C4973B360749B8")
       :to-equal record)))
  (it "finds the preferred SCHIP platform"
    (let ((record
            (cl-chip8:find-rom-record "f26993a4afd5cda2fea19935773fd3db54866623")))
      (expect (first (getf record :platforms)) :to-be :superchip)))
  (it "finds the preferred XO-CHIP platform"
    (let ((record
            (cl-chip8:find-rom-record "b693e60f161e69c98b0bb2bc1761cf434f8fbb0e")))
      (expect (first (getf record :platforms)) :to-be :xochip)))
  (it "contains default tickrates for all database platforms"
    (let* ((tickrates
             cl-chip8::*rom-database-platform-default-tickrates*)
           (platforms (mapcar #'car tickrates)))
      (expect (not (null tickrates)) :to-be t)
      (expect (length platforms) :to-be 9)
      (expect platforms :to-equal
              (list :original-chip8 :hybrid-vip :modern-chip8 :chip8x
                    :chip48 :superchip1 :superchip :megachip8 :xochip))
      (expect (mapcar #'cdr tickrates) :to-equal
              (list 15 15 12 15 30 30 30 1000 100))))
  (it "preserves an explicit false quirk override"
    (let* ((record
             (cl-chip8:find-rom-record "440c5fbe9f5f840e76c308738fb0d37772d66674"))
           (quirks (getf (getf record :quirky-platforms) :xochip))
           (wrap-entry (member :wrap quirks)))
      (expect (first (getf record :platforms)) :to-be :xochip)
      (expect (and wrap-entry (eq (first wrap-entry) :wrap)) :to-be t)
      (expect (second wrap-entry) :to-be nil)))
  (it "returns NIL for a valid unregistered SHA1"
    (expect
     (cl-chip8:find-rom-record "da39a3ee5e6b4b0d3255bfef95601890afd80709")
     :to-be nil))
  (it "hashes ROM bytes with SHA1"
    (let* ((record (list :platforms (list :synthetic) :tickrate 500))
           (cl-chip8::*rom-database-records*
             (list
              (cons "a9993e364706816aba3e25717850c26c9cd0d89d" record)))
           (bytes
             (make-array 3
                         :element-type (quote (unsigned-byte 8))
                         :initial-contents (vector 97 98 99))))
      (expect (cl-chip8:find-rom-record bytes) :to-equal record)
      (expect (aref bytes 0) :to-be 97)
      (expect (aref bytes 1) :to-be 98)
      (expect (aref bytes 2) :to-be 99))))
