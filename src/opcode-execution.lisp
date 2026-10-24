(in-package #:cl-chip8)

(declaim (inline advance-pc! %skip-if %vf-reset-if-needed %shift-source))

(defun advance-pc! (machine &optional (amount 2))
  (setf (chip8-machine-pc machine)
        (mod (+ (chip8-machine-pc machine) amount)
             (chip8-machine-memory-size machine))))

(defun %skip-if (machine condition)
  (advance-pc! machine
               (if condition
                   (let ((next-pc
                           (mod (+ (chip8-machine-pc machine) 2)
                                (chip8-machine-memory-size machine))))
                     (if (= (fetch-opcode machine next-pc) #xf000) 6 4))
                   2)))

(defun %vf-reset-if-needed (machine)
  (when (eq (chip8-quirks-vf-behavior (chip8-machine-quirks machine)) :reset)
    (setf (chip8-machine-register machine 15) 0)))

(defun %shift-source (machine x y)
  (if (eq (chip8-quirks-shift-source (chip8-machine-quirks machine)) :vy)
      (chip8-machine-register machine y)
      (chip8-machine-register machine x)))

(defun %schip-lores-scroll-distance (machine pixels)
  (if (and (eq (chip8-machine-resolution machine) :lores)
           (eq (chip8-quirks-lores-scroll (chip8-machine-quirks machine))
               :half))
      pixels
      (* pixels (if (eq (chip8-machine-resolution machine) :lores) 2 1))))

(defun %scroll-display! (machine horizontal vertical)
  (with-lock-held ((chip8-machine-framebuffer-lock machine))
    (let* ((framebuffer (chip8-machine-framebuffer machine))
           (height +physical-display-height+)
           (width +physical-display-width+)
           (plane-mask (chip8-machine-plane-mask machine))
           (source (make-array (list height width)
                               :element-type '(unsigned-byte 2))))
      (dotimes (y height)
        (dotimes (x width)
          (setf (aref source y x) (aref framebuffer y x))))
      (dotimes (y height)
        (dotimes (x width)
          (let* ((source-x (- x horizontal))
                 (source-y (- y vertical))
                 (selected
                   (if (and (<= 0 source-x) (< source-x width)
                            (<= 0 source-y) (< source-y height))
                       (logand plane-mask (aref source source-y source-x))
                       0)))
            (setf (aref framebuffer y x)
                  (logior (logandc2 (aref source y x) plane-mask)
                          selected))))))
  machine))

(defun %set-chip8-resolution-from-opcode! (machine resolution)
  (setf (chip8-machine-resolution-state machine) resolution)
  (when (chip8-quirks-mode-switch-clear (chip8-machine-quirks machine))
    (chip8-clear-display! machine))
  machine)
(defvar *chip8-rpl-flags*
  (make-array 16 :element-type 'chip8-octet :initial-element 0))

(defun %store-rpl-flags! (machine x)
  (dotimes (register (1+ x))
    (setf (aref *chip8-rpl-flags* register)
          (chip8-machine-register machine register))))

(defun %load-rpl-flags! (machine x)
  (dotimes (register (1+ x))
    (setf (chip8-machine-register machine register)
          (aref *chip8-rpl-flags* register))))

(defun %draw-vf-value (machine quirks collision-rows clipped-rows)
  (if (and (eq (chip8-quirks-collision quirks) :row-count)
           (eq (chip8-machine-resolution machine) :hires))
      (+ collision-rows clipped-rows)
      (if (plusp collision-rows) 1 0)))

(defun %draw-sprite! (machine x y n)
  (with-lock-held ((chip8-machine-framebuffer-lock machine))
    (let* ((quirks (chip8-machine-quirks machine))
           (lores-sprite (chip8-quirks-lores-sprite quirks))
           (logical-width (chip8-machine-logical-width machine))
           (logical-height (chip8-machine-logical-height machine))
           (sprite-width
             (if (plusp n)
                 8
                 (if (and (eq (chip8-machine-resolution machine) :lores)
                          (eq lores-sprite :8x16))
                     8
                     16)))
           (sprite-height (if (plusp n) n 16))
           (bytes-per-row (/ sprite-width 8))
           (plane-mask (chip8-machine-plane-mask machine))
           (plane-bytes (* bytes-per-row sprite-height))
           (sprite-bytes (* plane-bytes (logcount plane-mask)))
           (vx (mod (chip8-machine-register machine x) logical-width))
           (vy (mod (chip8-machine-register machine y) logical-height))
           (collision-rows 0)
           (clipped-rows
             (if (and (plusp plane-mask)
                      (eq (chip8-quirks-clipping quirks) :clip))
                 (max 0 (- (+ vy sprite-height) logical-height))
                 0))
           (i (chip8-machine-i machine)))
      (when (plusp sprite-bytes)
        (check-memory-access machine i sprite-bytes))
      (dotimes (row sprite-height)
        (let ((row-collision nil)
              (py (+ vy row)))
          (dolist (plane-bit '(1 2))
            (when (logtest plane-bit plane-mask)
              (let ((plane-offset
                      (if (and (= plane-mask 3) (= plane-bit 2))
                          plane-bytes
                          0)))
                (dotimes (byte-part bytes-per-row)
                  (let ((sprite-row
                          (memory-read machine
                                       (+ i plane-offset
                                          (* row bytes-per-row) byte-part))))
                    (dotimes (bit 8)
                      (when (logbitp (- 7 bit) sprite-row)
                        (let ((px (+ vx (* byte-part 8) bit)))
                          (when (eq (chip8-quirks-clipping quirks) :wrap)
                            (setf px (mod px logical-width)
                                  py (mod (+ vy row) logical-height)))
                          (when (and (< px logical-width)
                                     (< py logical-height)
                                     (%display-xor-pixel-unlocked!
                                      machine px py plane-bit))
                            (setf row-collision t))))))))))
          (when row-collision
            (incf collision-rows))))
      (setf (chip8-machine-register machine 15)
            (if (= plane-mask 3)
                (if (plusp collision-rows) 1 0)
                (%draw-vf-value machine quirks collision-rows clipped-rows))))))


(defun %store-registers! (machine x)
  (let ((i (chip8-machine-i machine)))
    (check-memory-access machine i (1+ x))
    (dotimes (register (1+ x))
      (setf (memory-read machine (+ i register))
            (chip8-machine-register machine register)))
    (let ((memory-i (chip8-quirks-memory-i (chip8-machine-quirks machine))))
      (when (member memory-i '(:increment :increment-x) :test #'eq)
        (setf (chip8-machine-i machine)
              (ldb (byte 16 0) (+ i x (if (eq memory-i :increment) 1 0))))))))

(defun %load-registers! (machine x)
  (let ((i (chip8-machine-i machine)))
    (check-memory-access machine i (1+ x))
    (dotimes (register (1+ x))
      (setf (chip8-machine-register machine register)
            (memory-read machine (+ i register))))
    (let ((memory-i (chip8-quirks-memory-i (chip8-machine-quirks machine))))
      (when (member memory-i '(:increment :increment-x) :test #'eq)
        (setf (chip8-machine-i machine)
              (ldb (byte 16 0) (+ i x (if (eq memory-i :increment) 1 0))))))))

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
                       (chip8-machine-pc machine)
                       (mod (+ pc 2) (chip8-machine-memory-size machine)))
                 t)))))))

(defun %install-display-wait! (machine)
  (let ((pc (chip8-machine-pc machine)))
    (setf (chip8-machine-waiting machine)
          (make-chip8-wait-state
           :kind :display :pc pc
           :continuation
           (lambda (event)
             (when (eq event :tick)
               (setf (chip8-machine-pc machine)
                     (mod (+ pc 2) (chip8-machine-memory-size machine)))
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

