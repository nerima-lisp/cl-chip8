(in-package #:cl-chip8/test)
(defun test-machine () (make-chip8-machine))
(defun test-opcode (machine opcode)
  (load-rom machine (vector (ldb (byte 8 8) opcode) (ldb (byte 8 0) opcode))
            :address (chip8-machine-pc machine))
  (execute-instruction! machine))
(defparameter *opcode-table-cases*
  (loop for profile in '(:modern :cosmac-vip) append
    (loop for opcode in '(#x00e0 #x00ee #x0123 #x1200 #x2200 #x2ffe #x3000 #x4000 #x5000
                          #x6000 #x7000 #x8000 #x8001 #x8002 #x8003 #x8004 #x8005
                          #x8006 #x8007 #x800e #x9000 #xa200 #xb200 #xc0ff #xd010
                          #xe09e #xe0a1 #xf007 #xf00a #xf015 #xf018 #xf01e #xf029
                          #xf033 #xf055 #xf065)
          collect (list profile opcode))))

(defparameter *opcode-semantic-cases*
  '((:add-register :add-register :modern #x8124
     :registers ((1 200) (2 56)) :vf 9 :pc #x202
     :results ((1 0) (15 1)))
    (:sub-register :sub-register :modern #x8125
     :registers ((1 10) (2 20)) :vf 9 :pc #x202
     :results ((1 246) (15 0)))
    (:subn-register :subn-register :modern #x8127
     :registers ((1 10) (2 20)) :vf 0 :pc #x202
     :results ((1 10) (15 1)))
    (:shr-vx :shr :modern #x8126
     :registers ((1 3) (2 128)) :vf 9 :pc #x202
     :results ((1 1) (15 1)))
    (:shr-vy :shr :cosmac-vip #x8126
     :registers ((1 3) (2 128)) :vf 9 :pc #x202
     :results ((1 64) (15 0)))
    (:or-preserves-vf :or :modern #x8121
     :registers ((1 1) (2 2)) :vf 9 :pc #x202
     :results ((1 3) (15 9)))
    (:or-resets-vf :or :cosmac-vip #x8121
     :registers ((1 1) (2 2)) :vf 9 :pc #x202
     :results ((1 3) (15 0)))
    (:add-i-preserves-vf :add-i :cosmac-vip #xf01e
     :vf 9 :pc #x202 :i #x300
     :registers ((1 5)) :results ((15 9)))
    (:skip-equal :se-byte :modern #x310a
     :registers ((1 10)) :vf 0 :pc #x204 :results nil)
    (:skip-not-equal :se-byte :modern #x310a
     :registers ((1 9)) :vf 0 :pc #x202 :results nil)
    (:jump-v0 :jp-v0 :modern #xb123
     :registers ((0 5)) :vf 0 :pc #x128 :results nil)
    (:draw-clip :draw :modern #xd011
     :registers ((0 63) (1 31)) :vf 0 :pc #x202 :i #x300
     :memory ((#x300 #xc0)) :pixels ((31 63 1) (31 0 0)) :results nil)
    (:draw-wrap :draw :modern #xd011
      :registers ((0 63) (1 31)) :vf 0 :pc #x202 :i #x300
      :overrides (:clipping :wrap) :memory ((#x300 #xc0))
      :pixels ((31 63 1) (31 0 1)) :results nil)
    (:store-increments-i :store-registers :modern #xf155
      :registers ((0 10) (1 20)) :vf 0 :pc #x202 :i #x300 :i-result #x300
      :memory-results ((#x300 10) (#x301 20)) :results nil)
    (:store-preserves-i :store-registers :cosmac-vip #xf155
      :registers ((0 10) (1 20)) :vf 0 :pc #x202 :i #x300 :i-result #x302
      :memory-results ((#x300 10) (#x301 20)) :results nil)
    (:load-increments-i :load-registers :modern #xf165
      :vf 0 :pc #x202 :i #x300 :i-result #x300
      :memory ((#x300 10) (#x301 20))
      :results ((0 10) (1 20)))
    (:load-preserves-i :load-registers :cosmac-vip #xf165
      :vf 0 :pc #x202 :i #x300 :i-result #x302
      :memory ((#x300 10) (#x301 20))
      :results ((0 10) (1 20)))))

(defun semantic-case-machine (case)
  (let ((machine
          (make-chip8-machine
           :quirks
           (apply #'make-chip8-quirks
                  :profile (third case)
                  (getf (cddddr case) :overrides)))))
    (dolist (entry (getf (cddddr case) :registers))
      (setf (chip8-machine-register machine (first entry)) (second entry)))
    (setf (chip8-machine-register machine 15) (getf (cddddr case) :vf)
          (chip8-machine-i machine)
          (or (getf (cddddr case) :i-initial)
              (getf (cddddr case) :i)
              0))
    (dolist (entry (getf (cddddr case) :memory))
      (setf (aref (chip8-machine-memory machine) (first entry)) (second entry)))
    machine))

(defun assert-semantic-case (case executor)
  (let ((machine (semantic-case-machine case)))
    (if (functionp executor)
        (funcall executor machine (fourth case))
        (test-opcode machine (fourth case)))
    (expect (chip8-machine-pc machine) :to-be (getf (cddddr case) :pc))
    (dolist (result (getf (cddddr case) :results))
      (expect (chip8-machine-register machine (first result))
              :to-be
              (second result)))
    (dolist (pixel (getf (cddddr case) :pixels))
      (expect (aref (chip8-machine-framebuffer machine)
                    (first pixel) (second pixel))
              :to-be
              (third pixel)))
    (when (or (getf (cddddr case) :i-result)
              (getf (cddddr case) :i))
      (expect (chip8-machine-i machine)
              :to-be
              (or (getf (cddddr case) :i-result)
                  (getf (cddddr case) :i))))
    (dolist (entry (getf (cddddr case) :memory-results))
      (expect (aref (chip8-machine-memory machine) (first entry))
              :to-be
              (second entry)))))

(it-each
    ((:add-register) (:sub-register) (:subn-register) (:shr-vx) (:shr-vy)
     (:or-preserves-vf) (:or-resets-vf) (:add-i-preserves-vf)
     (:skip-equal) (:skip-not-equal)
     (:jump-v0) (:draw-clip) (:draw-wrap) (:store-increments-i)
     (:store-preserves-i) (:load-increments-i) (:load-preserves-i))
  "checks opcode semantic boundary case ~A" (name)
  (assert-semantic-case
   (find name *opcode-semantic-cases* :key #'first)
   nil))
(describe "typed CHIP-8 machine"
  (it "resets to the documented initial state"
    (let ((m (test-machine)))
      (expect (chip8-machine-pc m) :to-be #x200) (expect (chip8-machine-i m) :to-be 0)
      (expect (chip8-machine-sp m) :to-be 0) (expect (chip8-machine-register m 0) :to-be 0)))
  (it "executes arithmetic and flow instructions"
    (let ((m (test-machine)))
      (test-opcode m #x6010) (test-opcode m #x7001)
      (expect (chip8-machine-register m 0) :to-be #x11)
      (test-opcode m #x1200) (expect (chip8-machine-pc m) :to-be #x200)))
  (it "snapshots framebuffer without aliasing"
    (let ((m (test-machine)))
      (setf (aref (chip8-machine-framebuffer m) 2 3) 1)
      (let ((copy (chip8-framebuffer m))) (setf (aref copy 2 3) 0) (expect (aref (chip8-machine-framebuffer m) 2 3) :to-be 1))))
  (it "signals stack and memory errors"
    (let ((m (test-machine))) (signals chip8-stack-underflow (test-opcode m #x00ee)) (signals chip8-memory-access-out-of-bounds (check-memory-access 4095 2)))))

(it-each
    ((:modern #x00e0) (:modern #x00ee) (:modern #x0123) (:modern #x1200) (:modern #x2200) (:modern #x2ffe) (:modern #x3000) (:modern #x4000) (:modern #x5000) (:modern #x6000) (:modern #x7000) (:modern #x8000) (:modern #x8001) (:modern #x8002) (:modern #x8003) (:modern #x8004) (:modern #x8005) (:modern #x8006) (:modern #x8007) (:modern #x800e) (:modern #x9000) (:modern #xa200) (:modern #xb200) (:modern #xc0ff) (:modern #xd010) (:modern #xe09e) (:modern #xe0a1) (:modern #xf007) (:modern #xf00a) (:modern #xf015) (:modern #xf018) (:modern #xf01e) (:modern #xf029) (:modern #xf033) (:modern #xf055) (:modern #xf065) (:cosmac-vip #x00e0) (:cosmac-vip #x00ee) (:cosmac-vip #x0123) (:cosmac-vip #x1200) (:cosmac-vip #x2200) (:cosmac-vip #x2ffe) (:cosmac-vip #x3000) (:cosmac-vip #x4000) (:cosmac-vip #x5000) (:cosmac-vip #x6000) (:cosmac-vip #x7000) (:cosmac-vip #x8000) (:cosmac-vip #x8001) (:cosmac-vip #x8002) (:cosmac-vip #x8003) (:cosmac-vip #x8004) (:cosmac-vip #x8005) (:cosmac-vip #x8006) (:cosmac-vip #x8007) (:cosmac-vip #x800e) (:cosmac-vip #x9000) (:cosmac-vip #xa200) (:cosmac-vip #xb200) (:cosmac-vip #xc0ff) (:cosmac-vip #xd010) (:cosmac-vip #xe09e) (:cosmac-vip #xe0a1) (:cosmac-vip #xf007) (:cosmac-vip #xf00a) (:cosmac-vip #xf015) (:cosmac-vip #xf018) (:cosmac-vip #xf01e) (:cosmac-vip #xf029) (:cosmac-vip #xf033) (:cosmac-vip #xf055) (:cosmac-vip #xf065))
  "executes opcode table case ~A ~4,'0X" (profile opcode)
  (let ((m (make-chip8-machine :quirks (make-chip8-quirks :profile profile))))
    (when (= opcode #x2ffe)
      (setf (chip8-machine-pc m) #xffe))
    (setf (chip8-machine-sp m) 1
          (aref (chip8-machine-stack m) 0) #x200)
    (test-opcode m opcode)
    (expect (chip8-machine-instructions m) :to-be 1)
    (expect (chip8-machine-pc m)
            :to-be
            (cond
              ((= opcode #x00ee) #x200)
              ((member opcode '(#x1200 #x2200 #xb200)) #x200)
              ((= opcode #x2ffe) #xffe)
              ((member opcode '(#x3000 #x5000 #xe0a1)) #x204)
              ((and (= opcode #xd010) (eq profile :cosmac-vip)) #x200)
              ((= opcode #xf00a) #x200)
              (t #x202)))
    (when (= opcode #x2ffe)
      (expect (aref (chip8-machine-stack m) 1) :to-be 0))))

(describe "CPU boundary and CPS contracts"
  (it "sets VF to carry for 8XY4 when X is F"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-register m 15) 200
            (chip8-machine-register m 1) 56)
      (test-opcode m #x8f14)
      (expect (chip8-machine-register m 15) :to-be 1)))
  (it "sets VF to borrow for 8XY5 when X is F"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-register m 15) 10
            (chip8-machine-register m 1) 20)
      (test-opcode m #x8f15)
      (expect (chip8-machine-register m 15) :to-be 0)))
  (it "sets VF to borrow flag for 8XY7 when X is F"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-register m 15) 20
            (chip8-machine-register m 1) 10)
      (test-opcode m #x8f17)
      (expect (chip8-machine-register m 15) :to-be 1)))
  (it "handles out-of-range keys in EX9E and EXA1"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-register m 0) 16)
      (test-opcode m #xe09e)
      (expect (chip8-machine-pc m) :to-be #x202)
      (setf (chip8-machine-pc m) #x200)
      (test-opcode m #xe0a1)
      (expect (chip8-machine-pc m) :to-be #x204)))
  (it "writes the shift result before VF when X is F"
    (let ((m (make-chip8-machine
              :quirks (make-chip8-quirks :profile :cosmac-vip))))
      (setf (chip8-machine-register m 1) #x83)
      (test-opcode m #x8f16)
      (expect (chip8-machine-register m 15) :to-be 1)
      (setf (chip8-machine-register m 1) #x81
            (chip8-machine-pc m) #x200)
      (test-opcode m #x8f1e)
      (expect (chip8-machine-register m 15) :to-be 1)))
  (it "wraps a CALL return address at the 12-bit boundary"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-pc m) #xffe)
      (test-opcode m #x2200)
      (expect (aref (chip8-machine-stack m) 0) :to-be 0)
      (test-opcode m #x00ee)
      (expect (chip8-machine-pc m) :to-be 0)))
  (it "wraps PC after the last two-byte instruction"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-pc m) #xffe)
      (load-rom m (vector #x60 #x00) :address #xffe)
      (execute-instruction! m)
      (expect (chip8-machine-pc m) :to-be 0)))
  (it "rejects a fetch starting at the final byte"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-pc m) #xfff)
      (signals chip8-memory-access-out-of-bounds (execute-instruction! m))))
  (it "rejects invalid and duplicate resumes"
    (let ((m (make-chip8-machine)))
      (test-opcode m #xf00a)
      (chip8-run-instructions m 1)
      (signals chip8-cps-error (chip8-resume! m '(:key-down 16)))
      (chip8-resume! m '(:key-down 3))
      (signals chip8-cps-error (chip8-resume! m '(:key-down 3))))))

(cl-weave:it-property
 "register writes remain octets"
 ((value (cl-weave:gen-integer :min 0 :max 65535)))
 (let ((m (make-chip8-machine)))
   (setf (chip8-machine-register m 0) value)
   (expect (<= 0 (chip8-machine-register m 0) 255) :to-be-truthy)))

(cl-weave:it-property
 "drawing the same pixel twice restores the framebuffer"
 ((x (cl-weave:gen-integer :min 0 :max 63))
  (y (cl-weave:gen-integer :min 0 :max 31)))
 (let ((m (make-chip8-machine)))
   (let ((before (chip8-framebuffer m)))
     (display-xor-pixel! m x y)
     (display-xor-pixel! m x y)
     (expect (loop for row below +display-height+
                   always (loop for column below +display-width+
                                always (= (aref (chip8-framebuffer m) row column)
                                          (aref before row column))))
             :to-be-truthy))))

(cl-weave:it-property
 "instruction flow preserves the 12-bit even PC invariant"
 ((word (cl-weave:gen-integer :min 0 :max 2047)))
 (let ((m (make-chip8-machine)) (pc (* 2 word)))
   (setf (chip8-machine-pc m) pc)
   (load-rom m (vector #x60 #x00) :address pc)
   (execute-instruction! m)
   (expect (< (chip8-machine-pc m) 4096) :to-be-truthy)
   (expect (evenp (chip8-machine-pc m)) :to-be-truthy)))

(defparameter *opcode-condition-cases*
  '((:invalid-low #x5f0f chip8-invalid-opcode)
    (:invalid-subopcode #x8f08 chip8-invalid-opcode)
    (:stack-overflow #x2200 chip8-stack-overflow)
    (:fetch-at-final-byte nil chip8-memory-access-out-of-bounds)))

(defun %condition-case (case)
  (destructuring-bind (name opcode condition) case
    (declare (ignore name))
    (let ((machine (make-chip8-machine))
          (caught nil))
      (if opcode
          (handler-case
              (progn
                (when (= opcode #x2200)
                  (setf (chip8-machine-sp machine) +call-stack-limit+))
                (test-opcode machine opcode))
            (chip8-error (value) (setf caught value)))
          (progn
            (setf (chip8-machine-pc machine) #xfff)
            (handler-case
                (execute-instruction! machine)
              (chip8-error (value) (setf caught value)))))
      (expect caught :to-be-type-of condition)
      (expect caught :to-be-truthy))))

(it "reports opcode execution conditions"
  (dolist (case *opcode-condition-cases*)
    (%condition-case case)))
