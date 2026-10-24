(in-package #:cl-chip8)

(defstruct (chip8-quirks (:constructor %make-chip8-quirks))
  (profile :modern :type (member :modern :cosmac-vip :schip :schip-legacy :xo-chip))
  (vf-behavior :preserve :type (member :preserve :reset))
  (memory-i :preserve :type (member :preserve :increment :increment-x))
  (display-wait :none :type (member :none :wait :lores-only))
  (clipping :clip :type (member :clip :wrap))
  (shift-source :vx :type (member :vx :vy))
  (bnnn-register :v0 :type (member :v0 :vx))
  (fx0a-completion :press :type (member :press :release))
  (lores-sprite :16x16 :type (member :16x16 :8x16))
  (collision :flag :type (member :flag :row-count))
  (lores-scroll :full :type (member :full :half))
  (mode-switch-clear t :type boolean))

(defparameter *chip8-quirk-slots*
  (quote ((:vf-behavior . chip8-quirks-vf-behavior)
          (:memory-i . chip8-quirks-memory-i)
          (:display-wait . chip8-quirks-display-wait)
          (:clipping . chip8-quirks-clipping)
          (:shift-source . chip8-quirks-shift-source)
          (:bnnn-register . chip8-quirks-bnnn-register)
          (:fx0a-completion . chip8-quirks-fx0a-completion)
          (:lores-sprite . chip8-quirks-lores-sprite)
          (:collision . chip8-quirks-collision)
          (:lores-scroll . chip8-quirks-lores-scroll)
          (:mode-switch-clear . chip8-quirks-mode-switch-clear))))

(defparameter *chip8-quirk-defaults*
  (quote ((:modern
           :vf-behavior :preserve
           :memory-i :preserve
           :display-wait :none
           :clipping :clip
           :shift-source :vx
           :bnnn-register :v0
           :fx0a-completion :press
           :lores-sprite :16x16
           :collision :flag
           :lores-scroll :full
           :mode-switch-clear t)
          (:cosmac-vip
           :vf-behavior :reset
           :memory-i :increment
           :display-wait :wait
           :clipping :clip
           :shift-source :vy
           :bnnn-register :v0
           :fx0a-completion :release
           :lores-sprite :16x16
           :collision :flag
           :lores-scroll :full
           :mode-switch-clear t)
          (:schip
           :vf-behavior :preserve
           :memory-i :preserve
           :display-wait :none
           :clipping :clip
           :shift-source :vy
           :bnnn-register :vx
           :fx0a-completion :press
           :lores-sprite :16x16
           :collision :flag
           :lores-scroll :full
           :mode-switch-clear t)
          (:schip-legacy
           :vf-behavior :preserve
           :memory-i :preserve
           :display-wait :lores-only
           :clipping :clip
           :shift-source :vy
           :bnnn-register :vx
           :fx0a-completion :press
           :lores-sprite :8x16
           :collision :row-count
           :lores-scroll :half
           :mode-switch-clear nil)
          (:xo-chip
           :vf-behavior :preserve
           :memory-i :increment
           :display-wait :none
           :clipping :wrap
           :shift-source :vx
           :bnnn-register :v0
           :fx0a-completion :press
           :lores-sprite :16x16
           :collision :flag
           :lores-scroll :full
           :mode-switch-clear t))))

(defun %chip8-quirk-defaults (profile)
  (or (cdr (assoc profile *chip8-quirk-defaults*))
      (%config-error (format nil "unknown quirk profile: ~S" profile)
                     :key :profile)))

(defun make-chip8-quirks (&key (profile :modern) vf-behavior memory-i display-wait
                                clipping shift-source bnnn-register fx0a-completion
                                lores-sprite collision lores-scroll
                                (mode-switch-clear nil mode-switch-clear-p))
  (let ((defaults (%chip8-quirk-defaults profile))
        (overrides
          (append
           (loop for (slot value) on (list :vf-behavior vf-behavior
                                           :memory-i memory-i
                                           :display-wait display-wait
                                           :clipping clipping
                                           :shift-source shift-source
                                           :bnnn-register bnnn-register
                                           :fx0a-completion fx0a-completion
                                           :lores-sprite lores-sprite
                                           :collision collision
                                           :lores-scroll lores-scroll)
                 by (function cddr)
                 unless (null value)
                   append (list slot value))
           (when mode-switch-clear-p
             (list :mode-switch-clear mode-switch-clear)))))
    (apply (function %make-chip8-quirks)
           :profile profile
           (loop for entry in *chip8-quirk-slots*
                 for slot = (car entry)
                 append (multiple-value-bind (indicator value)
                            (get-properties overrides (list slot))
                          (list slot (if indicator
                                         value
                                         (getf defaults slot))))))))

(defun merge-chip8-quirks (quirks &rest overrides)
  (apply (function make-chip8-quirks)
         :profile (chip8-quirks-profile quirks)
         (loop for (slot . accessor) in *chip8-quirk-slots*
               append (multiple-value-bind (indicator value)
                          (get-properties overrides (list slot))
                        (list slot (if indicator
                                       value
                                       (funcall accessor quirks)))))))
