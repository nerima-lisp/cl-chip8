(in-package #:cl-chip8)

(defun %resolve-chip8-platform (platform)
  (etypecase platform
    (chip8-platform platform)
    ((or keyword string)
     (or (find-chip8-platform platform)
         (error "Unknown CHIP-8 platform: ~S." platform)))))

(defun make-chip8-machine (&key (platform :modern)
                                (memory-size nil memory-size-p)
                                (quirks nil quirks-p))
  (let* ((platform (%resolve-chip8-platform platform))
         (memory-size (if memory-size-p
                          memory-size
                          (chip8-platform-memory-size platform)))
         (quirks (if quirks-p
                     (progn
                       (check-type quirks chip8-quirks)
                       quirks)
                     (chip8-platform-default-quirks platform))))
    (check-type memory-size (member 4096 65536))
    (let ((machine
            (%make-chip8-machine
             :platform platform
             :memory (make-array memory-size
                                 :element-type 'chip8-octet
                                 :initial-element 0)
             :quirks quirks)))
      (setf (chip8-machine-display-audio-lock machine)
            (make-lock :name "cl-chip8 display/audio"))
      (chip8-reset! machine))))

(defun chip8-machine-memory-size (machine)
  (length (chip8-machine-memory machine)))
(defun %chip8-machine-audio-snapshot (machine)
  (with-display-audio-lock ((chip8-machine-display-audio-lock machine))
    (values (chip8-platform-name (chip8-machine-platform machine))
            (chip8-machine-sound-timer machine)
            (copy-seq (chip8-machine-audio-pattern machine))
            (chip8-machine-pitch machine)
            (chip8-machine-xo-audio-instructions-used-p machine))))

(defun chip8-machine-logical-width (machine)
  (if (eq (chip8-machine-resolution machine) :hires)
      +physical-display-width+
      +display-width+))

(defun chip8-machine-logical-height (machine)
  (if (eq (chip8-machine-resolution machine) :hires)
      +physical-display-height+
      +display-height+))

(defun chip8-machine-resolution (machine)
  (chip8-machine-resolution-state machine))

(defun set-chip8-machine-resolution! (machine resolution)
  (check-type resolution (member :lores :hires))
  (unless (member resolution
                  (chip8-platform-resolutions (chip8-machine-platform machine))
                  :test #'eq)
    (error "Platform ~S does not support the ~S resolution."
           (chip8-platform-name (chip8-machine-platform machine))
           resolution))
  (setf (chip8-machine-resolution-state machine) resolution)
  machine)

(defun chip8-machine-plane-mask (machine)
  (chip8-machine-plane-mask-state machine))

(defun set-chip8-machine-plane-mask! (machine plane-mask)
  (check-type plane-mask (unsigned-byte 2))
  (setf (chip8-machine-plane-mask-state machine) plane-mask)
  machine)

(defun chip8-reset! (machine)
  (fill (chip8-machine-memory machine) 0)
  (fill (chip8-machine-v machine) 0)
  (fill (chip8-machine-stack machine) 0)
  (fill (chip8-machine-keypad machine) 0)
  (with-display-audio-lock ((chip8-machine-display-audio-lock machine))
    (fill (chip8-machine-audio-pattern machine) 0)
    (setf (chip8-machine-sound-timer machine) 0
          (chip8-machine-pitch machine) 64
          (chip8-machine-xo-audio-instructions-used-p machine) nil))
  (display-reset! machine)
  (set-chip8-machine-resolution! machine :lores)
  (set-chip8-machine-plane-mask! machine 1)
  (setf (chip8-machine-i machine) 0
        (chip8-machine-pc machine) +initial-pc+
        (chip8-machine-sp machine) 0
        (chip8-machine-delay-timer machine) 0
        (chip8-machine-halted-p machine) nil
        (chip8-machine-waiting machine) (make-chip8-wait-state)
        (chip8-machine-instructions machine) 0)
  (load-fontset-into-memory! machine)
  machine)

(defun chip8-machine-register (machine index)
  (check-type index (integer 0 15))
  (aref (chip8-machine-v machine) index))

(defun (setf chip8-machine-register) (value machine index)
  (check-type index (integer 0 15))
  (setf (aref (chip8-machine-v machine) index)
        (ldb (byte 8 0) value)))
