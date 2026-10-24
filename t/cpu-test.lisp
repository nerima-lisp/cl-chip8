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
    (:shr-vf-modern :shr :modern #x8ff6
     :registers () :vf 131 :pc #x202
     :results ((15 1)))
    (:shr-vf-cosmac-vip :shr :cosmac-vip #x8ff6
     :registers () :vf 131 :pc #x202
     :results ((15 1)))
    (:shl-vf-modern :shl :modern #x8ffe
     :registers () :vf 129 :pc #x202
     :results ((15 1)))
    (:shl-vf-cosmac-vip :shl :cosmac-vip #x8ffe
     :registers () :vf 129 :pc #x202
     :results ((15 1)))
    (:or-preserves-vf :or :modern #x8121
     :registers ((1 1) (2 2)) :vf 9 :pc #x202
     :results ((1 3) (15 9)))
    (:or-resets-vf :or :cosmac-vip #x8121
     :registers ((1 1) (2 2)) :vf 9 :pc #x202
     :results ((1 3) (15 0)))
    (:or-vf-modern-x :or :modern #x8ef1
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((14 15) (15 10)))
    (:or-vf-modern-y :or :modern #x8fe1
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((15 15)))
    (:or-vf-modern-both :or :modern #x8ff1
     :registers () :vf 10 :pc #x202
     :results ((15 10)))
    (:or-vf-cosmac-vip-x :or :cosmac-vip #x8ef1
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((14 15) (15 0)))
    (:or-vf-cosmac-vip-y :or :cosmac-vip #x8fe1
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((15 0)))
    (:or-vf-cosmac-vip-x-reset :or :cosmac-vip #x8f11
     :registers ((1 5)) :vf 10 :pc #x202
     :results ((15 0)))
    (:or-vf-cosmac-vip-both :or :cosmac-vip #x8ff1
     :registers () :vf 10 :pc #x202
     :results ((15 0)))
    (:and-vf-modern-x :and :modern #x8ef2
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((14 0) (15 10)))
    (:and-vf-modern-y :and :modern #x8fe2
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((15 0)))
    (:and-vf-modern-both :and :modern #x8ff2
     :registers () :vf 10 :pc #x202
     :results ((15 10)))
    (:and-vf-cosmac-vip-x :and :cosmac-vip #x8ef2
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((14 0) (15 0)))
    (:and-vf-cosmac-vip-y :and :cosmac-vip #x8fe2
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((15 0)))
    (:and-vf-cosmac-vip-both :and :cosmac-vip #x8ff2
     :registers () :vf 10 :pc #x202
     :results ((15 0)))
    (:xor-vf-modern-x :xor :modern #x8ef3
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((14 15) (15 10)))
    (:xor-vf-modern-y :xor :modern #x8fe3
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((15 15)))
    (:xor-vf-modern-both :xor :modern #x8ff3
     :registers () :vf 10 :pc #x202
     :results ((15 0)))
    (:xor-vf-cosmac-vip-x :xor :cosmac-vip #x8ef3
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((14 15) (15 0)))
    (:xor-vf-cosmac-vip-y :xor :cosmac-vip #x8fe3
     :registers ((14 5)) :vf 10 :pc #x202
     :results ((15 0)))
    (:xor-vf-cosmac-vip-both :xor :cosmac-vip #x8ff3
     :registers () :vf 10 :pc #x202
     :results ((15 0)))
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
    (:store-preserves-i :store-registers :modern #xf155
      :registers ((0 10) (1 20)) :vf 0 :pc #x202 :i #x300 :i-result #x300
      :memory-results ((#x300 10) (#x301 20)) :results nil)
    (:store-increments-i :store-registers :cosmac-vip #xf155
      :registers ((0 10) (1 20)) :vf 0 :pc #x202 :i #x300 :i-result #x302
      :memory-results ((#x300 10) (#x301 20)) :results nil)
    (:load-preserves-i :load-registers :modern #xf165
      :vf 0 :pc #x202 :i #x300 :i-result #x300
      :memory ((#x300 10) (#x301 20))
      :results ((0 10) (1 20)))
    (:load-increments-i :load-registers :cosmac-vip #xf165
      :vf 0 :pc #x202 :i #x300 :i-result #x302
      :memory ((#x300 10) (#x301 20))
      :results ((0 10) (1 20)))
    (:scroll-down-schip :scroll-down :modern #x00c2
     :platform :schip :resolution :hires :plane-mask 1 :vf 0 :pc #x202
     :initial-pixels ((10 4 1) (62 9 1))
     :pixels ((12 4 1) (10 4 0) (63 9 0)) :results nil)
    (:scroll-right-schip :scroll-right :modern #x00fb
     :platform :schip :resolution :hires :plane-mask 1 :vf 0 :pc #x202
     :initial-pixels ((7 2 1) (10 127 1))
     :pixels ((7 6 1) (7 2 0) (10 127 0)) :results nil)
    (:scroll-left-schip :scroll-left :modern #x00fc
     :platform :schip :resolution :hires :plane-mask 1 :vf 0 :pc #x202
     :initial-pixels ((9 5 1))
     :pixels ((9 1 1) (9 5 0)) :results nil)
    (:halt-schip :halt :modern #x00fd
     :platform :schip :vf 0 :status :halted :results nil)
    (:lores-schip :lores :modern #x00fe
     :platform :schip :resolution :hires :resolution-result :lores
     :vf 0 :pc #x202 :results nil)
    (:hires-schip :hires :modern #x00ff
     :platform :schip :resolution :lores :resolution-result :hires
     :vf 0 :pc #x202 :results nil)
    (:draw-schip-16x16 :draw :modern #xd010
     :platform :schip :resolution :lores
     :registers ((0 3) (1 4)) :vf 7 :pc #x202 :i #x300
     :memory ((#x300 #x80) (#x301 #x40) (#x302 #x20) (#x303 #x10)
              (#x304 #x08) (#x305 #x04) (#x306 #x02) (#x307 #x01)
              (#x308 #xff) (#x309 #x00) (#x30a #x18) (#x30b #x24)
              (#x30c #x42) (#x30d #x81) (#x30e #xaa) (#x30f #x55)
              (#x310 0) (#x311 0) (#x312 0) (#x313 0)
              (#x314 0) (#x315 0) (#x316 0) (#x317 0)
              (#x318 0) (#x319 0) (#x31a 0) (#x31b 0)
              (#x31c 0) (#x31d 0) (#x31e #x01) (#x31f #x80))
     :pixels ((4 3 1) (4 4 0) (4 11 0) (4 12 1)
              (5 5 1) (5 6 0) (5 13 0) (5 14 1)
              (6 7 1) (6 16 1) (7 9 1) (7 18 1)
              (8 3 1) (8 10 1) (8 11 0)
              (9 6 1) (9 7 1) (9 13 1) (9 16 1)
              (10 4 1) (10 9 1) (10 11 1) (10 18 1)
              (11 3 1) (11 5 1) (11 7 1) (11 9 1)
              (11 12 1) (11 14 1) (11 16 1) (11 18 1)
              (18 10 0) (19 9 0) (19 10 1) (19 11 1))
     :results ((15 0)))
    (:ld-big-font :ld-big-font :modern #xf030
     :platform :schip :registers ((0 15)) :vf 0 :pc #x202
     :i-initial #x300 :i-result #x136 :results nil)
    (:store-rpl-sixteen :store-rpl :modern #xff75
     :platform :schip :registers ((0 0) (1 17) (2 34) (3 51)
                                  (4 68) (5 85) (6 102) (7 119)
                                  (8 136) (9 153) (10 170) (11 187)
                                  (12 204) (13 221) (14 238))
     :vf 255 :pc #x204 :rpl-seed (0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
     :follow-up-opcode #xff85
     :results ((0 0) (1 17) (2 34) (3 51) (4 68) (5 85) (6 102) (7 119)
               (8 136) (9 153) (10 170) (11 187) (12 204) (13 221)
               (14 238) (15 255)))
    (:load-rpl-sixteen :load-rpl :modern #xff85
     :platform :schip :vf 0 :pc #x202
     :rpl-seed (0 17 34 51 68 85 102 119 136 153 170 187 204 221 238 255)
     :results ((0 0) (1 17) (2 34) (3 51) (4 68) (5 85) (6 102) (7 119)
               (8 136) (9 153) (10 170) (11 187) (12 204) (13 221)
               (14 238) (15 255)))))
(defun semantic-case-machine (case)
  (let* ((arguments (cddddr case))
         (machine
           (make-chip8-machine
            :platform (or (getf arguments :platform) :modern)
            :quirks
            (apply #'make-chip8-quirks
                   :profile (third case)
                   (getf arguments :overrides)))))
    (dolist (entry (getf arguments :registers))
      (setf (chip8-machine-register machine (first entry)) (second entry)))
    (setf (chip8-machine-register machine 15) (getf arguments :vf)
          (chip8-machine-i machine)
          (or (getf arguments :i-initial)
              (getf arguments :i)
              0))
    (dolist (entry (getf arguments :memory))
      (setf (aref (chip8-machine-memory machine) (first entry)) (second entry)))
    (when (getf arguments :resolution)
      (set-chip8-machine-resolution! machine (getf arguments :resolution)))
    (when (getf arguments :plane-mask)
      (set-chip8-machine-plane-mask! machine (getf arguments :plane-mask)))
    (dolist (pixel (getf arguments :initial-pixels))
      (display-xor-pixel! machine (second pixel) (first pixel) (third pixel)))
    machine))

(defun assert-semantic-case (case executor)
  (let* ((arguments (cddddr case))
         (machine (semantic-case-machine case)))
    (when (getf arguments :rpl-seed)
      (let ((seed-machine
              (make-chip8-machine
               :platform (chip8-machine-platform machine)
               :quirks (chip8-machine-quirks machine))))
        (loop for value in (getf arguments :rpl-seed)
              for index from 0
              do (setf (chip8-machine-register seed-machine index) value))
        (test-opcode seed-machine #xff75)))
    (if (functionp executor)
        (funcall executor machine (fourth case))
        (test-opcode machine (fourth case)))
    (when (getf arguments :follow-up-opcode)
      (test-opcode machine (getf arguments :follow-up-opcode)))
    (when (member :pc arguments)
      (expect (chip8-machine-pc machine) :to-be (getf arguments :pc)))
    (when (member :status arguments)
      (expect (chip8-run-result-status (chip8-run-instructions machine 0))
              :to-be
              (getf arguments :status)))
    (dolist (result (getf arguments :results))
      (expect (chip8-machine-register machine (first result))
              :to-be
              (second result)))
    (dolist (pixel (getf arguments :pixels))
      (expect (display-pixel-value machine (second pixel) (first pixel))
              :to-be
              (third pixel)))
    (when (or (getf arguments :i-result)
              (getf arguments :i))
      (expect (chip8-machine-i machine)
              :to-be
              (or (getf arguments :i-result)
                  (getf arguments :i))))
    (when (getf arguments :resolution-result)
      (expect (chip8-machine-resolution machine)
              :to-be
              (getf arguments :resolution-result)))
    (when (getf arguments :plane-mask-result)
      (expect (chip8-machine-plane-mask machine)
              :to-be
              (getf arguments :plane-mask-result)))
    (dolist (entry (getf arguments :memory-results))
      (expect (aref (chip8-machine-memory machine) (first entry))
              :to-be
              (second entry)))))

(it-each
    ((:add-register) (:sub-register) (:subn-register) (:shr-vx) (:shr-vy)
 (:shr-vf-modern) (:shr-vf-cosmac-vip) (:shl-vf-modern) (:shl-vf-cosmac-vip)
 (:or-preserves-vf) (:or-resets-vf)
 (:or-vf-modern-x) (:or-vf-modern-y) (:or-vf-modern-both)
 (:or-vf-cosmac-vip-x) (:or-vf-cosmac-vip-y) (:or-vf-cosmac-vip-both)
 (:or-vf-cosmac-vip-x-reset)
 (:and-vf-modern-x) (:and-vf-modern-y) (:and-vf-modern-both)
 (:and-vf-cosmac-vip-x) (:and-vf-cosmac-vip-y) (:and-vf-cosmac-vip-both)
 (:xor-vf-modern-x) (:xor-vf-modern-y) (:xor-vf-modern-both)
 (:xor-vf-cosmac-vip-x) (:xor-vf-cosmac-vip-y) (:xor-vf-cosmac-vip-both)
 (:add-i-preserves-vf)
 (:skip-equal) (:skip-not-equal)
 (:jump-v0) (:draw-clip) (:draw-wrap) (:draw-schip-16x16)
 (:scroll-down-schip) (:scroll-right-schip) (:scroll-left-schip)
 (:halt-schip) (:lores-schip) (:hires-schip) (:ld-big-font)
 (:store-rpl-sixteen) (:load-rpl-sixteen)
 (:store-increments-i) (:store-preserves-i) (:load-increments-i) (:load-preserves-i))
  "checks opcode semantic boundary case ~A" (name)
  (assert-semantic-case
   (find name *opcode-semantic-cases* :key #'first)
   nil))
(describe "typed CHIP-8 machine"
  (it "resets to the documented initial state"
    (let ((m (test-machine)))
      (expect (chip8-machine-pc m) :to-be #x200)
      (expect (chip8-machine-i m) :to-be 0)
      (expect (chip8-machine-sp m) :to-be 0)
      (expect (chip8-machine-register m 0) :to-be 0)))
  (it "executes arithmetic and flow instructions"
    (let ((m (test-machine)))
      (test-opcode m #x6010)
      (test-opcode m #x7001)
      (expect (chip8-machine-register m 0) :to-be #x11)
      (test-opcode m #x1200)
      (expect (chip8-machine-pc m) :to-be #x200)))
  (it "snapshots framebuffer without aliasing"
    (let ((m (test-machine)))
      (setf (aref (chip8-machine-framebuffer m) 2 3) 1)
      (let ((copy (chip8-framebuffer-snapshot m)))
        (setf (aref copy 1 1) 0)
        (expect (aref (chip8-framebuffer-snapshot m) 1 1) :to-be 1))))
  (it "signals stack and memory errors"
    (let ((m (test-machine)))
      (signals chip8-stack-underflow (test-opcode m #x00ee))
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access m 4095 2)))))

(it-each
        ((:modern #x00e0)
     (:modern #x00ee)
     (:modern #x0123)
     (:modern #x1200)
     (:modern #x2200)
     (:modern #x2ffe)
     (:modern #x3000)
     (:modern #x4000)
     (:modern #x5000)
     (:modern #x6000)
     (:modern #x7000)
     (:modern #x8000)
     (:modern #x8001)
     (:modern #x8002)
     (:modern #x8003)
     (:modern #x8004)
     (:modern #x8005)
     (:modern #x8006)
     (:modern #x8007)
     (:modern #x800e)
     (:modern #x9000)
     (:modern #xa200)
     (:modern #xb200)
     (:modern #xc0ff)
     (:modern #xd010)
     (:modern #xe09e)
     (:modern #xe0a1)
     (:modern #xf007)
     (:modern #xf00a)
     (:modern #xf015)
     (:modern #xf018)
     (:modern #xf01e)
     (:modern #xf029)
     (:modern #xf033)
     (:modern #xf055)
     (:modern #xf065)
     (:modern #x00c2)
     (:modern #x00fb)
     (:modern #x00fc)
     (:modern #x00fd)
     (:modern #x00fe)
     (:modern #x00ff)
     (:modern #xd000)
     (:modern #xf030)
     (:modern #xff75)
     (:modern #xff85)
     (:cosmac-vip #x00e0)
     (:cosmac-vip #x00ee)
     (:cosmac-vip #x0123)
     (:cosmac-vip #x1200)
     (:cosmac-vip #x2200)
     (:cosmac-vip #x2ffe)
     (:cosmac-vip #x3000)
     (:cosmac-vip #x4000)
     (:cosmac-vip #x5000)
     (:cosmac-vip #x6000)
     (:cosmac-vip #x7000)
     (:cosmac-vip #x8000)
     (:cosmac-vip #x8001)
     (:cosmac-vip #x8002)
     (:cosmac-vip #x8003)
     (:cosmac-vip #x8004)
     (:cosmac-vip #x8005)
     (:cosmac-vip #x8006)
     (:cosmac-vip #x8007)
     (:cosmac-vip #x800e)
     (:cosmac-vip #x9000)
     (:cosmac-vip #xa200)
     (:cosmac-vip #xb200)
     (:cosmac-vip #xc0ff)
     (:cosmac-vip #xd010)
     (:cosmac-vip #xe09e)
     (:cosmac-vip #xe0a1)
     (:cosmac-vip #xf007)
     (:cosmac-vip #xf00a)
     (:cosmac-vip #xf015)
     (:cosmac-vip #xf018)
     (:cosmac-vip #xf01e)
     (:cosmac-vip #xf029)
     (:cosmac-vip #xf033)
     (:cosmac-vip #xf055)
     (:cosmac-vip #xf065)
     (:cosmac-vip #x00c2)
     (:cosmac-vip #x00fb)
     (:cosmac-vip #x00fc)
     (:cosmac-vip #x00fd)
     (:cosmac-vip #x00fe)
     (:cosmac-vip #x00ff)
     (:cosmac-vip #xd000)
     (:cosmac-vip #xf030)
     (:cosmac-vip #xff75)
     (:cosmac-vip #xff85)
    )
  "executes opcode table case ~A ~4,'0X" (profile opcode)
  (let* ((platform (if (member opcode '(#x00fe #x00ff)) :schip :modern))
         (m (make-chip8-machine
             :platform platform
             :quirks (make-chip8-quirks :profile profile))))
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
              ((and (member opcode '(#xd000 #xd010))
                    (eq profile :cosmac-vip))
               #x200)
              ((= opcode #xf00a) #x200)
              (t #x202)))
    (when (= opcode #x2ffe)
      (expect (aref (chip8-machine-stack m) 1) :to-be 0))))

(describe "CPU boundary and CPS contracts"
  (it "wraps a CALL return address at the 12-bit boundary"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-pc m) #xffe)
      (test-opcode m #x2200)
      (expect (aref (chip8-machine-stack m) 0) :to-be 0)
      (test-opcode m #x00ee)
      (expect (chip8-machine-pc m) :to-be 0)))
  (it "wraps PC after the last two-byte instruction in a default 4K machine"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-pc m) #xffe)
      (load-rom m (vector #x60 #x00) :address #xffe)
      (execute-instruction! m)
      (expect (chip8-machine-pc m) :to-be 0)))
  (it "rejects a fetch starting at the final byte of default 4K memory"
    (let ((m (make-chip8-machine)))
      (setf (chip8-machine-pc m) #xfff)
      (signals chip8-memory-access-out-of-bounds (execute-instruction! m))))
  (it "wraps PC after the last instruction in 64K memory"
    (let ((m (make-chip8-machine :platform :xo-chip)))
      (setf (chip8-machine-pc m) #xfffe)
      (load-rom m (vector #x60 #x00) :address #xfffe)
      (execute-instruction! m)
      (expect (chip8-machine-pc m) :to-be 0)))
  (it "preserves a 16-bit PC in the XO key wait state"
    (let ((m (make-chip8-machine
              :platform :xo-chip
              :quirks (make-chip8-quirks :profile :modern
                                         :fx0a-completion :press))))
      (setf (chip8-machine-pc m) #xfffe)
      (load-rom m (vector #xf0 #x0a) :address #xfffe)
      (execute-instruction! m)
      (expect (chip8-wait-state-pc (chip8-machine-waiting m))
              :to-be #xfffe)
      (chip8-resume! m '(:key-down 3))
      (expect (chip8-machine-pc m) :to-be 0)
      (expect (chip8-machine-register m 0) :to-be 3)))
  (it "rejects invalid and duplicate resumes"
    (let ((m (make-chip8-machine)))
      (test-opcode m #xf00a)
      (chip8-run-instructions m 1)
      (signals chip8-cps-error (chip8-resume! m '(:key-down 16)))
      (chip8-resume! m '(:key-down 3))
      (signals chip8-cps-error (chip8-resume! m '(:key-down 3))))))
(describe "SCHIP Phase 2 opcode behavior"
  (it "returns a halted run result for 00FD on the modern platform"
    (let ((machine (make-chip8-machine :platform :modern)))
      (load-rom machine (vector #x00 #xfd))
      (let ((result (chip8-run-instructions machine 1)))
        (expect (chip8-run-result-status result) :to-be :halted)
        (expect (chip8-run-result-executed result) :to-be 1))))
  (it "loads all sixteen Octo big-font glyphs below 0x200"
    (let ((machine (make-chip8-machine :platform :schip))
          (glyphs #(#(#xff #xff #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xff #xff)
                    #(#x18 #x78 #x78 #x18 #x18 #x18 #x18 #x18 #xff #xff)
                    #(#xff #xff #x03 #x03 #xff #xff #xc0 #xc0 #xff #xff)
                    #(#xff #xff #x03 #x03 #xff #xff #x03 #x03 #xff #xff)
                    #(#xc3 #xc3 #xc3 #xc3 #xff #xff #x03 #x03 #x03 #x03)
                    #(#xff #xff #xc0 #xc0 #xff #xff #x03 #x03 #xff #xff)
                    #(#xff #xff #xc0 #xc0 #xff #xff #xc3 #xc3 #xff #xff)
                    #(#xff #xff #x03 #x03 #x06 #x0c #x18 #x18 #x18 #x18)
                    #(#xff #xff #xc3 #xc3 #xff #xff #xc3 #xc3 #xff #xff)
                    #(#xff #xff #xc3 #xc3 #xff #xff #x03 #x03 #xff #xff)
                    #(#x7e #xff #xc3 #xc3 #xc3 #xff #xff #xc3 #xc3 #xc3)
                    #(#xfc #xfc #xc3 #xc3 #xfc #xfc #xc3 #xc3 #xfc #xfc)
                    #(#x3c #xff #xc3 #xc0 #xc0 #xc0 #xc0 #xc3 #xff #x3c)
                    #(#xfc #xfe #xc3 #xc3 #xc3 #xc3 #xc3 #xc3 #xfe #xfc)
                    #(#xff #xff #xc0 #xc0 #xff #xff #xc0 #xc0 #xff #xff)
                    #(#xff #xff #xc0 #xc0 #xff #xff #xc0 #xc0 #xc0 #xc0)))
          (base nil))
      (loop for glyph across glyphs
            for digit from 0
            do (setf (chip8-machine-register machine 0) digit)
               (test-opcode machine #xf030)
               (let ((address (chip8-machine-i machine)))
                 (unless base
                   (setf base address))
                 (expect address :to-be (+ base (* digit 10)))
                 (dotimes (row 10)
                   (expect (aref (chip8-machine-memory machine) (+ address row))
                           :to-be
                           (aref glyph row)))))
      (expect (<= (+ base 160) #x200) :to-be-truthy)
      (expect (<= #xa0 base) :to-be-truthy)))
  (it "persists all sixteen RPL flags across machine instances"
    (let ((store-machine (make-chip8-machine :platform :schip))
          (expected #(#x00 #x11 #x22 #x33 #x44 #x55 #x66 #x77
                      #x88 #x99 #xaa #xbb #xcc #xdd #xee #xff)))
      (loop for value across expected
            for index from 0
            do (setf (chip8-machine-register store-machine index) value))
      (test-opcode store-machine #xff75)
      (let ((load-machine (make-chip8-machine :platform :schip)))
        (test-opcode load-machine #xff85)
        (loop for value across expected
              for index from 0
              do (expect (chip8-machine-register load-machine index)
                         :to-be
                         value)))))
  (it "clears both planes when entering lores mode"
    (let* ((machine (make-chip8-machine :platform :schip))
           (framebuffer (chip8-machine-framebuffer machine)))
      (set-chip8-machine-resolution! machine :hires)
      (setf (aref framebuffer 3 7) #b01
            (aref framebuffer 4 8) #b10)
      (test-opcode machine #x00fe)
      (expect (chip8-machine-resolution machine) :to-be :lores)
      (expect (aref framebuffer 3 7) :to-be 0)
      (expect (aref framebuffer 4 8) :to-be 0)))
  (it "executes extended quirk values on their affected opcodes"
    (let ((store-machine
            (make-chip8-machine
             :platform :modern
             :quirks (make-chip8-quirks :profile :modern
                                        :memory-i :increment-x)))
          (load-machine
            (make-chip8-machine
             :platform :modern
             :quirks (make-chip8-quirks :profile :modern
                                        :memory-i :increment-x))))
      (setf (chip8-machine-i store-machine) #x300
            (chip8-machine-register store-machine 0) 10
            (chip8-machine-register store-machine 1) 20)
      (test-opcode store-machine #xf155)
      (expect (chip8-machine-i store-machine) :to-be #x301)
      (expect (list (aref (chip8-machine-memory store-machine) #x300)
                    (aref (chip8-machine-memory store-machine) #x301))
              :to-equal '(10 20))
      (setf (chip8-machine-i load-machine) #x300
            (aref (chip8-machine-memory load-machine) #x300) 10
            (aref (chip8-machine-memory load-machine) #x301) 20)
      (test-opcode load-machine #xf165)
      (expect (chip8-machine-i load-machine) :to-be #x301)
      (expect (list (chip8-machine-register load-machine 0)
                    (chip8-machine-register load-machine 1))
              :to-equal '(10 20)))
    (dolist (case '((:lores :display #x200)
                    (:hires nil #x202)))
      (destructuring-bind (resolution expected-wait expected-pc) case
        (let ((machine
                (make-chip8-machine
                 :platform :schip
                 :quirks (make-chip8-quirks :profile :modern
                                            :display-wait :lores-only))))
          (set-chip8-machine-resolution! machine resolution)
          (setf (chip8-machine-i machine) #x300
                (aref (chip8-machine-memory machine) #x300) #x80)
          (test-opcode machine #xd010)
          (expect (if (chip8-machine-waiting machine) (cl-chip8::chip8-wait-state-kind (chip8-machine-waiting machine)) nil)
                  :to-be expected-wait)
          (expect (chip8-machine-pc machine) :to-be expected-pc))))
    (let ((machine
            (make-chip8-machine
             :platform :schip
             :quirks (make-chip8-quirks :profile :modern
                                        :lores-sprite :8x16))))
      (setf (chip8-machine-i machine) #x300
            (aref (chip8-machine-memory machine) #x300) #x80
            (aref (chip8-machine-memory machine) #x301) #x40)
      (test-opcode machine #xd010)
      (expect (display-pixel-value machine 0 0) :to-be 1)
      (expect (display-pixel-value machine 1 0) :to-be 0)
      (expect (display-pixel-value machine 0 1) :to-be 0)
      (expect (display-pixel-value machine 1 1) :to-be 1))
    (let ((machine (make-chip8-machine :platform :schip-legacy)))
      (set-chip8-machine-resolution! machine :hires)
      (setf (chip8-machine-i machine) #x300
            (aref (chip8-machine-memory machine) #x300) #x80
            (aref (chip8-machine-memory machine) #x302) #x80
            (aref (chip8-machine-memory machine) #x304) #x40)
      (display-xor-pixel! machine 0 0)
      (display-xor-pixel! machine 0 1)
      (display-xor-pixel! machine 1 2)
      (test-opcode machine #xd010)
      (progn
        (expect (chip8-machine-register machine 15) :to-be 3)
        (setf (chip8-machine-register machine 1) 63)
        (test-opcode machine #xd010)
        (expect (chip8-machine-register machine 15) :to-be 15)))
    (let ((machine (make-chip8-machine :platform :schip-legacy)))
      (setf (chip8-machine-i machine) #x300
            (aref (chip8-machine-memory machine) #x300) #x80
            (aref (chip8-machine-memory machine) #x301) #x80)
      (display-xor-pixel! machine 0 0)
      (display-xor-pixel! machine 0 1)
      (test-opcode machine #xd010)
      (expect (chip8-machine-register machine 15) :to-be 1))
    (dolist (case '((:half 5) (:full 6)))
      (destructuring-bind (lores-scroll expected-y) case
        (let ((machine
                (make-chip8-machine
                 :platform :schip
                 :quirks (make-chip8-quirks :profile :modern
                                            :lores-scroll lores-scroll))))
          (display-xor-pixel! machine 3 4)
          (test-opcode machine #x00c2)
          (expect (display-pixel-value machine 3 4) :to-be 0)
          (expect (display-pixel-value machine 3 expected-y) :to-be 1))))
    (let ((machine
            (make-chip8-machine
             :platform :schip
             :quirks (make-chip8-quirks :profile :modern
                                        :mode-switch-clear nil))))
      (set-chip8-machine-resolution! machine :hires)
      (setf (aref (chip8-machine-framebuffer machine) 12 10) 1)
      (test-opcode machine #x00fe)
      (expect (chip8-machine-resolution machine) :to-be :lores)
      (expect (aref (chip8-machine-framebuffer machine) 12 10) :to-be 1))))
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
   (let ((before (chip8-framebuffer-snapshot m)))
     (display-xor-pixel! m x y)
     (display-xor-pixel! m x y)
     (expect (equalp (chip8-framebuffer-snapshot m) before)
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
