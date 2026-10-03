(in-package #:cl-chip8)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *chip8-opcode-definitions* nil))

(defmacro define-chip8-opcode (name pattern mask fields &body body)
  (let ((definition `(:name ,name :pattern ,pattern :mask ,mask
                       :fields ,fields :body ,body)))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (pushnew ',definition *chip8-opcode-definitions*
                :key (lambda (entry) (getf entry :name))
                :test #'eq))))

(define-chip8-opcode cls #x00e0 #xffff ()
  (chip8-clear-display! machine)
  (advance-pc! machine))

(define-chip8-opcode ret #x00ee #xffff ()
  (when (zerop (chip8-machine-sp machine))
    (error 'chip8-stack-underflow))
  (decf (chip8-machine-sp machine))
  (setf (chip8-machine-pc machine)
        (aref (chip8-machine-stack machine) (chip8-machine-sp machine))))

(define-chip8-opcode sys #x0000 #xf000 ()
  (advance-pc! machine))

(define-chip8-opcode jp #x1000 #xf000 ((nnn (ldb (byte 12 0) opcode)))
  (setf (chip8-machine-pc machine) nnn))

(define-chip8-opcode call #x2000 #xf000 ((nnn (ldb (byte 12 0) opcode)))
  (let ((sp (chip8-machine-sp machine)))
    (when (>= sp +call-stack-limit+)
      (error 'chip8-stack-overflow :depth sp))
    (setf (aref (chip8-machine-stack machine) sp)
          (mod (+ (chip8-machine-pc machine) 2) +memory-size+)
          (chip8-machine-sp machine) (1+ sp)
          (chip8-machine-pc machine) nnn)))

(define-chip8-opcode se-byte #x3000 #xf000
    ((x (ldb (byte 4 8) opcode)) (kk (ldb (byte 8 0) opcode)))
  (%skip-if machine (= (chip8-machine-register machine x) kk)))

(define-chip8-opcode sne-byte #x4000 #xf000
    ((x (ldb (byte 4 8) opcode)) (kk (ldb (byte 8 0) opcode)))
  (%skip-if machine (/= (chip8-machine-register machine x) kk)))

(define-chip8-opcode se-register #x5000 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (%skip-if machine (= (chip8-machine-register machine x)
                       (chip8-machine-register machine y))))

(define-chip8-opcode ld-byte #x6000 #xf000
    ((x (ldb (byte 4 8) opcode)) (kk (ldb (byte 8 0) opcode)))
  (setf (chip8-machine-register machine x) kk)
  (advance-pc! machine))

(define-chip8-opcode add-byte #x7000 #xf000
    ((x (ldb (byte 4 8) opcode)) (kk (ldb (byte 8 0) opcode)))
  (incf (chip8-machine-register machine x) kk)
  (advance-pc! machine))

(define-chip8-opcode ld-register #x8000 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (setf (chip8-machine-register machine x)
        (chip8-machine-register machine y))
  (advance-pc! machine))

(define-chip8-opcode or #x8001 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((vx (chip8-machine-register machine x))
        (vy (chip8-machine-register machine y)))
    (setf (chip8-machine-register machine x) (logior vx vy))
    (%vf-reset-if-needed machine))
  (advance-pc! machine))

(define-chip8-opcode and #x8002 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((vx (chip8-machine-register machine x))
        (vy (chip8-machine-register machine y)))
    (setf (chip8-machine-register machine x) (logand vx vy))
    (%vf-reset-if-needed machine))
  (advance-pc! machine))

(define-chip8-opcode xor #x8003 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((vx (chip8-machine-register machine x))
        (vy (chip8-machine-register machine y)))
    (setf (chip8-machine-register machine x) (logxor vx vy))
    (%vf-reset-if-needed machine))
  (advance-pc! machine))

(define-chip8-opcode add-register #x8004 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((sum (+ (chip8-machine-register machine x)
                (chip8-machine-register machine y))))
    (setf (chip8-machine-register machine x) sum
          (chip8-machine-register machine 15) (if (> sum 255) 1 0)))
  (advance-pc! machine))

(define-chip8-opcode sub-register #x8005 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((vx (chip8-machine-register machine x))
        (vy (chip8-machine-register machine y)))
    (setf (chip8-machine-register machine x) (- vx vy)
          (chip8-machine-register machine 15) (if (>= vx vy) 1 0)))
  (advance-pc! machine))

(define-chip8-opcode shr #x8006 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((source (%shift-source machine x y)))
    (let ((flag (logand source 1))
          (result (ash source -1)))
      (setf (chip8-machine-register machine x) result
            (chip8-machine-register machine 15) flag)))
  (advance-pc! machine))

(define-chip8-opcode subn-register #x8007 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((vx (chip8-machine-register machine x))
        (vy (chip8-machine-register machine y)))
    (setf (chip8-machine-register machine x) (- vy vx)
          (chip8-machine-register machine 15) (if (>= vy vx) 1 0)))
  (advance-pc! machine))

(define-chip8-opcode shl #x800e #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (let ((source (%shift-source machine x y)))
    (let ((flag (ldb (byte 1 7) source))
          (result (ash source 1)))
      (setf (chip8-machine-register machine x) result
            (chip8-machine-register machine 15) flag)))
  (advance-pc! machine))

(define-chip8-opcode sne-register #x9000 #xf00f
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode)))
  (%skip-if machine (/= (chip8-machine-register machine x)
                        (chip8-machine-register machine y))))

(define-chip8-opcode ld-i #xa000 #xf000
    ((nnn (ldb (byte 12 0) opcode)))
  (setf (chip8-machine-i machine) nnn)
  (advance-pc! machine))

(define-chip8-opcode jp-v0 #xb000 #xf000
    ((x (ldb (byte 4 8) opcode)) (nnn (ldb (byte 12 0) opcode)))
  (let ((base (if (eq (chip8-quirks-bnnn-register
                       (chip8-machine-quirks machine)) :vx)
                  (chip8-machine-register machine x)
                  (chip8-machine-register machine 0))))
    (setf (chip8-machine-pc machine)
          (mod (+ nnn base) +memory-size+))))

(define-chip8-opcode random #xc000 #xf000
    ((x (ldb (byte 4 8) opcode)) (kk (ldb (byte 8 0) opcode)))
  (setf (chip8-machine-register machine x) (logand (chip8-random-byte machine) kk))
  (advance-pc! machine))

(define-chip8-opcode draw #xd000 #xf000
    ((x (ldb (byte 4 8) opcode)) (y (ldb (byte 4 4) opcode))
     (n (ldb (byte 4 0) opcode)))
  (%draw-sprite! machine x y n)
  (if (eq (chip8-quirks-display-wait (chip8-machine-quirks machine)) :wait)
      (%install-display-wait! machine)
      (advance-pc! machine)))

(define-chip8-opcode skip-key #xe09e #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (%skip-if machine
            (key-down-p machine (chip8-machine-register machine x))))

(define-chip8-opcode skip-not-key #xe0a1 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (%skip-if machine
            (not (key-down-p machine (chip8-machine-register machine x)))))

(define-chip8-opcode ld-delay #xf007 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (setf (chip8-machine-register machine x)
        (chip8-machine-delay-timer machine))
  (advance-pc! machine))

(define-chip8-opcode wait-key #xf00a #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (%execute-fx0a machine x))

(define-chip8-opcode ld-delay-from-vx #xf015 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (setf (chip8-machine-delay-timer machine)
        (chip8-machine-register machine x))
  (advance-pc! machine))

(define-chip8-opcode ld-sound-from-vx #xf018 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (setf (chip8-machine-sound-timer machine)
        (chip8-machine-register machine x))
  (advance-pc! machine))

(define-chip8-opcode add-i #xf01e #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (setf (chip8-machine-i machine)
        (ldb (byte 16 0)
             (+ (chip8-machine-i machine)
                (chip8-machine-register machine x))))
  (advance-pc! machine))

(define-chip8-opcode ld-font #xf029 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (setf (chip8-machine-i machine)
        (+ +fontset-address+
           (* 5 (mod (chip8-machine-register machine x) 16))))
  (advance-pc! machine))

(define-chip8-opcode bcd #xf033 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (let ((value (chip8-machine-register machine x))
        (i (chip8-machine-i machine)))
    (check-memory-access i 3)
    (setf (memory-read machine i) (floor value 100)
          (memory-read machine (1+ i)) (mod (floor value 10) 10)
          (memory-read machine (+ i 2)) (mod value 10)))
  (advance-pc! machine))

(define-chip8-opcode store-registers #xf055 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (%store-registers! machine x)
  (advance-pc! machine))

(define-chip8-opcode load-registers #xf065 #xf0ff
    ((x (ldb (byte 4 8) opcode)))
  (%load-registers! machine x)
  (advance-pc! machine))

(defun opcode-x (opcode) (ldb (byte 4 8) opcode))
(defun opcode-y (opcode) (ldb (byte 4 4) opcode))
(defun opcode-n (opcode) (ldb (byte 4 0) opcode))
(defun opcode-kk (opcode) (ldb (byte 8 0) opcode))
(defun opcode-nnn (opcode) (ldb (byte 12 0) opcode))
