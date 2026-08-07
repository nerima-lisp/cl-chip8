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

(describe
  "hand-authored integration ROM"
  (before-each (reset-machine!))
  (it
    "computes V0=8, draws one pixel, and loops in place once it gets there"
    (load-fontset-into-memory!)
    (setf (aref *memory* #x300) #x80)
    (load-bytes-into-memory
      (make-array
        14
        :element-type
        (quote (unsigned-byte 8))
        :initial-contents
        (quote (#x60 #x05 #x61 #x03 #x80 #x14 #x62 #x02 #xA3 #x00 #xD0 #x21 #x12 #x0C)))
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
    (execute-instruction!)
    (expect (pc-value) :to-be (+ +rom-load-address+ 12)))
  (it
    "schedules the configured CPU rate without treating CHIP-8 q as quit"
    (flet ((instructions-over-sixty-ticks (clock-hz)
             (let ((app (make-chip8-app :clock-hz clock-hz)))
               (loop repeat 60
                     sum (cl-chip8::%instructions-per-tick app)))))
      (with-soft-assertions
        (expect (instructions-over-sixty-ticks 700) :to-be 700)
        (expect (instructions-over-sixty-ticks 1) :to-be 1)
        (expect
          (quit-key-event-p (make-key-event :type :special :code :escape))
          :to-be
          t)
        (expect
          (quit-key-event-p (make-key-event :type :character :code (code-char 113)))
          :to-be
          nil)))))

(describe "terminal sound signalling" (before-each (reset-machine!)) (it "emits one BEL every six frames while the sound timer is active" (let ((app (make-chip8-app))) (set-sound-timer! 1) (expect (cl-chip8::%sound-bell-prefix app) :to-equal (string #\Bell)) (expect (loop repeat 5 always (string= (cl-chip8::%sound-bell-prefix app) "")) :to-be t) (expect (cl-chip8::%sound-bell-prefix app) :to-equal (string #\Bell)) (set-sound-timer! 0) (expect (cl-chip8::%sound-bell-prefix app) :to-equal ""))))
(describe
  "sound timer tick ordering"
  (before-each (reset-machine!))
  (it
    "renders an FX18 value of one for at least one frame"
    (load-bytes-into-memory
      (make-array
        4
        :element-type
        (quote (unsigned-byte 8))
        :initial-contents
        (quote (#x60 #x01 #xF0 #x18)))
      +rom-load-address+)
    (let ((app (make-chip8-app
                 :decoder (cl-tty-kit:make-input-decoder)
                 :clock-hz 60))
          (*standard-input* (make-string-input-stream "")))
      (cl-chip8::%advance-chip8! app)
      (cl-chip8::%advance-chip8! app)
      (with-soft-assertions
        (expect (sound-timer-active-p) :to-be t)
        (expect (cl-chip8::%sound-bell-prefix app) :to-equal (string #\Bell))))))
(describe
  "application tick loop input"
  (before-each (reset-machine!))
  (it
    "quits from a standalone Escape after the following idle poll"
    (load-bytes-into-memory
      (make-array
        2
        :element-type
        (quote (unsigned-byte 8))
        :initial-contents
        (quote (#x60 #x01)))
      +rom-load-address+)
    (let ((app (make-chip8-app
                 :decoder (cl-tty-kit:make-input-decoder)
                 :clock-hz 60)))
      (let ((*standard-input* (make-string-input-stream (string #\Escape))))
        (cl-tty-kit:tick-loop-run
          app
          (function cl-chip8::%advance-chip8!)
          2))
      (with-soft-assertions
        (expect (chip8-app-quitp app) :to-be t)
        (expect (register-value 0) :to-be 1)))))
