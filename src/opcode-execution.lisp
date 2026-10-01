(in-package #:cl-chip8)

(declaim (inline advance-pc! %skip-if %vf-reset-if-needed %shift-source))

(defun advance-pc! (machine &optional (amount 2))
  (setf (chip8-machine-pc machine)
        (mod (+ (chip8-machine-pc machine) amount) +memory-size+)))

(defun %skip-if (machine condition)
  (advance-pc! machine (if condition 4 2)))

(defun %vf-reset-if-needed (machine)
  (when (eq (chip8-quirks-vf-behavior (chip8-machine-quirks machine)) :reset)
    (setf (chip8-machine-register machine 15) 0)))

(defun %shift-source (machine x y)
  (if (eq (chip8-quirks-shift-source (chip8-machine-quirks machine)) :vy)
      (chip8-machine-register machine y)
      (chip8-machine-register machine x)))

(defun %draw-sprite! (machine x y n)
  (with-lock-held ((chip8-machine-framebuffer-lock machine))
    (let* ((quirks (chip8-machine-quirks machine))
           (i (chip8-machine-i machine))
           (vx (mod (chip8-machine-register machine x) +display-width+))
           (vy (mod (chip8-machine-register machine y) +display-height+))
           (collision nil))
      (check-memory-access i n)
      (dotimes (row n)
        (let ((sprite-row (memory-read machine (+ i row))))
          (dotimes (bit 8)
            (when (logbitp (- 7 bit) sprite-row)
              (let ((px (+ vx bit)) (py (+ vy row)))
                (when (eq (chip8-quirks-clipping quirks) :wrap)
                  (setf px (mod px +display-width+)
                        py (mod py +display-height+)))
                (when (and (< px +display-width+)
                           (< py +display-height+)
                           (%display-xor-pixel-unlocked! machine px py))
                  (setf collision t)))))))
      (setf (chip8-machine-register machine 15) (if collision 1 0)))))

(defun %store-registers! (machine x)
  (let ((i (chip8-machine-i machine)))
    (check-memory-access i (1+ x))
    (dotimes (register (1+ x))
      (setf (memory-read machine (+ i register))
            (chip8-machine-register machine register)))
    (when (eq (chip8-quirks-memory-i (chip8-machine-quirks machine)) :increment)
      (setf (chip8-machine-i machine) (ldb (byte 16 0) (+ i x 1))))))

(defun %load-registers! (machine x)
  (let ((i (chip8-machine-i machine)))
    (check-memory-access i (1+ x))
    (dotimes (register (1+ x))
      (setf (chip8-machine-register machine register)
            (memory-read machine (+ i register))))
    (when (eq (chip8-quirks-memory-i (chip8-machine-quirks machine)) :increment)
      (setf (chip8-machine-i machine) (ldb (byte 16 0) (+ i x 1))))))

(defun %install-key-wait! (machine x)
  (let ((pc (chip8-machine-pc machine)))
    (setf (chip8-machine-waiting machine)
          (make-chip8-wait-state
           :kind :key :pc pc :register x
           :continuation
           (lambda (event)
             (destructuring-bind (kind key) event
               (when (or (and (eq kind :key-down)
                              (eq (chip8-quirks-fx0a-completion
                                   (chip8-machine-quirks machine)) :press))
                         (and (eq kind :key-up)
                              (eq (chip8-quirks-fx0a-completion
                                   (chip8-machine-quirks machine)) :release)))
                 (setf (chip8-machine-register machine x) key
                       (chip8-machine-pc machine) (mod (+ pc 2) +memory-size+))
                 t)))))))

(defun %install-display-wait! (machine)
  (let ((pc (chip8-machine-pc machine)))
    (setf (chip8-machine-waiting machine)
          (make-chip8-wait-state
           :kind :display :pc pc
           :continuation
           (lambda (event)
             (when (eq event :tick)
               (setf (chip8-machine-pc machine) (mod (+ pc 2) +memory-size+))
               t))))))

(defun %execute-fx0a (machine x)
  (let ((keys (pressed-keys machine)))
    (if (and keys
             (eq (chip8-quirks-fx0a-completion
                  (chip8-machine-quirks machine)) :press))
        (progn
          (setf (chip8-machine-register machine x) (first keys))
          (advance-pc! machine))
        (%install-key-wait! machine x))))
