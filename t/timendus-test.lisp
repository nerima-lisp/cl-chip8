(in-package #:cl-chip8/test)

(defun timendus-directory ()
  (or (uiop:getenv "CHIP8_TIMENDUS_DIR")
      (when (string= (uiop:getenv "CHIP8_TIMENDUS_SKIP") "1")
        (skip "CHIP8_TIMENDUS_DIR is not configured"))
      (error "CHIP8_TIMENDUS_DIR is required; set CHIP8_TIMENDUS_SKIP=1 only for non-conformance local runs")))

(defun timendus-rom (name)
  (let ((path (pathname (format nil "~A/~A.ch8" (timendus-directory) name))))
    (unless (probe-file path)
      (error "Timendus ROM is missing: ~A" path))
    path))

(defun framebuffer-ascii (framebuffer)
  (with-output-to-string (out)
    (dotimes (y +display-height+)
      (dotimes (x +display-width+)
        (write-char (if (plusp (aref framebuffer y x)) #\# #\.) out))
      (terpri out))))

(defparameter *timendus-quirk-flag-rows*
  '((:vf-reset . 2)
    (:memory . 7)
    (:display-wait . 12)
    (:clipping . 17)
    (:shifting . 22)
    (:jumping . 27)))

(defparameter *timendus-quirk-flag-expectations*
  '((:modern
     (:vf-reset :err)
     (:memory :err)
     (:display-wait :err)
     (:clipping :ok)
     (:shifting :err)
     (:jumping :ok))
    (:cosmac-vip
     (:vf-reset :ok)
     (:memory :ok)
     (:display-wait :ok)
     (:clipping :ok)
     (:shifting :ok)
     (:jumping :ok))))

(defun timendus-flag-row-mask (framebuffer y)
  (loop for x from 59 below 64
        for bit from 0
        when (plusp (aref framebuffer y x))
          sum (ash 1 bit)))

(defun timendus-quirk-flag (framebuffer y)
  (let ((rows (list (timendus-flag-row-mask framebuffer y)
                    (timendus-flag-row-mask framebuffer (1+ y))
                    (timendus-flag-row-mask framebuffer (+ y 2)))))
    (cond ((equal (subseq rows 0 2) '(5 3)) :ok)
          ((equal (subseq rows 0 2) '(5 2)) :err)
          (t (list :unknown rows)))))

(defun run-timendus (name profile)
  (let ((machine (make-chip8-machine :quirks (make-chip8-quirks :profile profile))))
    (load-rom-file machine (timendus-rom name))
    (when (string= name "5-quirks")
      (setf (aref (chip8-machine-memory machine) #x1ff) 1))
    (if (string= name "5-quirks")
        (chip8-run-ticks machine 10000 :instructions-per-tick 100)
        (loop repeat (if (member name '("3-corax+" "4-flags") :test #'string=) 5000 500)
              for result = (chip8-run-instructions machine 1)
              do (when (eq (chip8-run-result-status result) :waiting)
                   (chip8-resume! machine :tick))))
    machine))

(describe "Timendus CHIP-8 test suite v4.2"
  (it-each
    (("1-chip8-logo" :modern) ("1-chip8-logo" :cosmac-vip)
     ("2-ibm-logo" :modern) ("2-ibm-logo" :cosmac-vip)
     ("3-corax+" :modern) ("3-corax+" :cosmac-vip)
     ("4-flags" :modern) ("4-flags" :cosmac-vip)
     ("5-quirks" :modern) ("5-quirks" :cosmac-vip))
    "runs ~A under ~A and matches the framebuffer golden"
    (name profile)
     (expect (framebuffer-ascii (chip8-framebuffer (run-timendus name profile)))
            :to-match-snapshot
            (format nil "timendus/~A/~A" name profile)))

  (it-each
    ((:modern :vf-reset) (:modern :memory) (:modern :display-wait)
     (:modern :clipping) (:modern :shifting) (:modern :jumping)
     (:cosmac-vip :vf-reset) (:cosmac-vip :memory)
     (:cosmac-vip :display-wait) (:cosmac-vip :clipping)
     (:cosmac-vip :shifting) (:cosmac-vip :jumping))
    "reports the ~A ~A quirk flag"
    (profile quirk)
    (let* ((machine (run-timendus "5-quirks" profile))
           (framebuffer (chip8-framebuffer machine))
           (y (cdr (assoc quirk *timendus-quirk-flag-rows*)))
           (expected (second (assoc quirk
                                    (cdr (assoc profile
                                                *timendus-quirk-flag-expectations*))))))
      (expect (eq (timendus-quirk-flag framebuffer y) expected) :to-be-truthy)))

  (it "injects keypad input through the headless API"
    (let ((machine (make-chip8-machine)))
      (load-rom-file machine (timendus-rom "6-keypad"))
      (chip8-key-down! machine 1)
      (chip8-run-instructions machine 200)
      (chip8-key-up! machine 1)
      (chip8-run-instructions machine 200)
      (dolist (key '(2 3 12 4 5 6 13 7 8 9 14 10 0 11 15))
        (chip8-key-down! machine key)
        (chip8-run-instructions machine 200)
        (chip8-key-up! machine key)
        (chip8-run-instructions machine 200))
      (expect (chip8-machine-instructions machine) :to-satisfy (lambda (n) (> n 100))))))
