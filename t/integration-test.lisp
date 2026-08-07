;;;; t/integration-test.lisp -- one small, hand-authored end-to-end ROM: set
;;;; two registers, add them, draw a single pixel, and loop in place.
;;;;
;;;; The program (at +ROM-LOAD-ADDRESS+ = 0x200):
;;;;
;;;;   0x200  6005  LD V0, 5
;;;;   0x202  6103  LD V1, 3
;;;;   0x204  8014  ADD V0, V1      ; V0 = 8
;;;;   0x206  6202  LD V2, 2
;;;;   0x208  A300  LD I, 0x300     ; a one-row sprite (0x80) lives there
;;;;   0x20A  D021  DRW V0, V2, 1   ; draw at (8, 2)
;;;;   0x20C  120C  JP 0x20C        ; loop in place forever
(in-package #:cl-chip8/test)

(describe "hand-authored integration ROM"
  (it "computes V0=8, draws one pixel, and loops in place once it gets there"
    (reset-machine!)
    (load-fontset-into-memory!)
    (setf (aref *memory* #x300) #x80)
    (load-bytes-into-memory
     (make-array 14 :element-type '(unsigned-byte 8)
                 :initial-contents '(#x60 #x05
                                     #x61 #x03
                                     #x80 #x14
                                     #x62 #x02
                                     #xA3 #x00
                                     #xD0 #x21
                                     #x12 #x0C))
     +rom-load-address+)
    (dotimes (i 6)
      (execute-instruction!))
    (with-soft-assertions
      (expect (register-value 0) :to-be 8)
      (expect (register-value 1) :to-be 3)
      (expect (register-value 2) :to-be 2)
      (expect (i-register-value) :to-be #x300)
      (expect (display-pixel-value 8 2) :to-be 1)
      (expect (pc-value) :to-be (+ +rom-load-address+ 12)))
    ;; The JP at the end targets itself: PC should be unchanged after one
    ;; more instruction, and every step after that.
    (execute-instruction!)
    (expect (pc-value) :to-be (+ +rom-load-address+ 12))))
