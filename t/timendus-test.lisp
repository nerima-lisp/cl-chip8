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
(defun timendus-framebuffer (machine)
  (chip8-framebuffer machine))
;; Glyphs and masks follow Timendus v4.2 src/tests/3-corax+.8o, src/tests/4-flags.8o, src/tests/6-keypad.8o, src/tests/7-beep.8o, and src/utils/text-rendering.8o.
(defun timendus-glyph-matches-p (framebuffer x y rows)
  (loop for row in rows
        for row-offset from 0
        always (loop for column below 3
                     always (char= (char row column)
                                   (if (plusp (aref framebuffer
                                                    (+ y row-offset)
                                                    (+ x column)))
                                       (code-char 49)
                                       (code-char 48))))))
(defun timendus-result-glyph-at (framebuffer x y)
  (cond
    ((timendus-glyph-matches-p framebuffer x y
                               (quote ("000" "101" "110" "100")))
     :ok)
    ((timendus-glyph-matches-p framebuffer x y
                               (quote ("000" "101" "010" "101")))
     :err)
    ((timendus-glyph-matches-p framebuffer x y
                               (quote ("101" "110" "100")))
     :ok)
    ((timendus-glyph-matches-p framebuffer x y
                               (quote ("101" "010" "101")))
     :err)
    (t :unknown)))
(defun timendus-result-grid-p (framebuffer coordinates expected)
  (every (lambda (origin)
           (destructuring-bind (x y) origin
             (eq (timendus-result-glyph-at framebuffer x y) expected)))
         coordinates))
(defun timendus-keypad-framebuffer (active-keys)
  (let ((framebuffer (make-array (quote (32 64))
                                 :element-type (quote bit)
                                 :initial-element 0)))
    (dolist (key active-keys)
      (destructuring-bind (x y)
          (nth key
               (quote ((24 23) (16 2) (24 2) (32 2)
                       (16 9) (24 9) (32 9) (16 16)
                       (24 16) (32 16) (16 23) (32 23)
                       (40 2) (40 9) (40 16) (40 23))))
        (dotimes (row 6)
          (dotimes (column 7)
            (setf (sbit framebuffer (+ y row) (+ x column)) 1)))))
    framebuffer))
(defun timendus-keypad-machine (profile mode active-keys)
  (let ((machine (make-chip8-machine
                  :quirks (make-chip8-quirks :profile profile))))
    (load-rom-file machine (timendus-rom "6-keypad"))
    (setf (aref (chip8-machine-memory machine) #x1ff) mode)
    (dolist (key active-keys)
      (chip8-key-down! machine key))
    (chip8-run-ticks machine 1000 :instructions-per-tick 100)
    machine))
(defun timendus-beep-samples (profile)
  (let* ((machine (make-chip8-machine
                   :quirks (make-chip8-quirks :profile profile)))
         (started nil)
         (sound-starts 0)
         (previous-timer 0)
         (samples nil))
    (load-rom-file machine (timendus-rom "7-beep"))
    (loop repeat 1000
          do (chip8-run-ticks machine 1 :instructions-per-tick 100)
             (let ((timer (chip8-machine-sound-timer machine)))
               (when (and (plusp timer)
                          (or (not started) (zerop previous-timer)))
                 (incf sound-starts))
               (when (= sound-starts 10)
                 (return))
               (when (or started (plusp timer))
                 (setf started t)
                 (push (plusp timer) samples))
               (setf previous-timer timer)))
    (nreverse samples)))
(defun timendus-beep-expected-timeline (profile)
  (loop for (sound gap) in (quote ((10 5) (10 5) (10 20)
                                   (30 5) (30 5) (30 20)
                                   (10 5) (10 5) (10 60)))
        append (make-list sound :initial-element t)
        append (make-list (+ gap (if (eq profile :cosmac-vip) 2 0))
                          :initial-element nil)))

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
    (expect (framebuffer-ascii (timendus-framebuffer
                                (run-timendus name profile)))
            :to-match-snapshot
            (format nil "timendus/~A/~A" name profile)))

  (it-each
    ((:modern) (:cosmac-vip))
    "decodes all 22 3-corax+ result markers under ~A"
    (profile)
    (expect (timendus-result-grid-p
             (timendus-framebuffer (run-timendus "3-corax+" profile))
             (quote ((11 1) (27 1) (43 1) (59 1)
                     (11 6) (27 6) (43 6) (59 6)
                     (11 11) (27 11) (43 11) (59 11)
                     (11 16) (27 16) (43 16) (59 16)
                     (11 21) (27 21) (43 21)
                     (11 26) (27 26) (43 26)))
             :ok)
            :to-be-truthy))

  (it-each
    ((:modern) (:cosmac-vip))
    "decodes all 47 4-flags result markers under ~A"
    (profile)
    (expect (timendus-result-grid-p
             (timendus-framebuffer (run-timendus "4-flags" profile))
             (quote ((27 1) (31 1) (35 1) (49 1) (53 1) (57 1)
                     (5 6) (9 6) (13 6) (27 6) (31 6) (35 6) (39 6)
                     (49 6) (53 6) (57 6) (61 6)
                     (5 11) (9 11) (13 11) (27 11) (31 11) (35 11)
                     (39 11) (49 11) (53 11) (57 11)
                     (27 17) (31 17) (35 17) (39 17)
                     (49 17) (53 17) (57 17) (61 17)
                     (5 22) (9 22) (13 22) (27 22) (31 22) (35 22)
                     (39 22) (49 22) (53 22) (57 22)
                     (31 28) (35 28)))
             :ok)
            :to-be-truthy))

  (it-each
    ((:modern :vf-reset) (:modern :memory) (:modern :display-wait)
     (:modern :clipping) (:modern :shifting) (:modern :jumping)
     (:cosmac-vip :vf-reset) (:cosmac-vip :memory)
     (:cosmac-vip :display-wait) (:cosmac-vip :clipping)
     (:cosmac-vip :shifting) (:cosmac-vip :jumping))
    "reports the ~A ~A quirk flag"
    (profile quirk)
    (let* ((machine (run-timendus "5-quirks" profile))
           (framebuffer (timendus-framebuffer machine))
           (y (cdr (assoc quirk *timendus-quirk-flag-rows*)))
           (expected (second (assoc quirk
                                    (cdr (assoc profile
                                                *timendus-quirk-flag-expectations*))))))
      (expect (eq (timendus-quirk-flag framebuffer y) expected) :to-be-truthy)))

  (it-each
    ((:modern "EX9E" :pressed) (:cosmac-vip "EX9E" :pressed)
     (:modern "EXA1" :released) (:cosmac-vip "EXA1" :released))
    "profile ~A executes ~A and lights cursor cells for keys that are ~A"
    (profile opcode key-state)
    (let* ((mode (if (string= opcode "EX9E") 1 2))
           (pressed-keys (quote (0 2 4 6 8 10 12 14)))
           (all-keys (loop for key below 16 collect key))
           (highlighted-keys
             (ecase key-state
               (:pressed pressed-keys)
               (:released (set-difference all-keys pressed-keys))))
           (baseline-keys
             (ecase key-state
               (:pressed nil)
               (:released all-keys)))
           (active-framebuffer
             (timendus-framebuffer
              (timendus-keypad-machine profile mode pressed-keys)))
           (baseline-framebuffer
             (timendus-framebuffer
              (timendus-keypad-machine profile mode baseline-keys)))
           (difference
             (make-array (quote (32 64))
                         :element-type (quote bit)
                         :initial-contents
                         (loop for y below 32
                               collect (loop for x below 64
                                             collect (if (= (aref active-framebuffer y x)
                                                            (aref baseline-framebuffer y x))
                                                         0
                                                         1))))))
      (expect (equalp difference
                      (timendus-keypad-framebuffer highlighted-keys))
              :to-be-truthy)))

  (it-each
    ((:cosmac-vip :ok) (:modern :err))
    "mode 3 reports the profile-specific FX0A result for ~A"
    (profile expected)
    (let ((machine (make-chip8-machine
                    :quirks (make-chip8-quirks :profile profile))))
      (load-rom-file machine (timendus-rom "6-keypad"))
      (setf (aref (chip8-machine-memory machine) #x1ff) 3)
      (let ((result (chip8-run-ticks machine 1000 :instructions-per-tick 100)))
        (expect (chip8-run-result-status result) :to-be :waiting)
        (expect (chip8-machine-delay-timer machine) :to-be 3))
      (loop for expected-delay in (quote (2 1 0))
            for result = (chip8-run-ticks machine 1 :instructions-per-tick 100)
            do (expect (chip8-run-result-status result) :to-be :waiting)
               (expect (chip8-machine-delay-timer machine)
                       :to-be expected-delay))
      (chip8-key-down! machine 1)
      (chip8-resume! machine (quote (:key-down 1)))
      (when (eq profile :cosmac-vip)
        (let ((result (chip8-run-instructions machine 1)))
          (expect (chip8-run-result-status result) :to-be :waiting)
          (expect (chip8-machine-delay-timer machine) :to-be 0)
          (expect (timendus-result-glyph-at (timendus-framebuffer machine) 30 9)
                  :to-be :unknown))
        (chip8-key-up! machine 1)
        (chip8-resume! machine (quote (:key-up 1))))
      (loop repeat 1000
            until (member (timendus-result-glyph-at
                           (timendus-framebuffer machine) 30 9)
                          (quote (:ok :err)))
            do (chip8-run-ticks machine 1 :instructions-per-tick 100))
      (expect (timendus-result-glyph-at (timendus-framebuffer machine) 30 9)
              :to-be expected)))

  (it-each
    ((:modern) (:cosmac-vip))
    "checks every SOS sound-on tick and silent gap under ~A"
    (profile)
    (expect (timendus-beep-samples profile)
            :to-equal (timendus-beep-expected-timeline profile))))
