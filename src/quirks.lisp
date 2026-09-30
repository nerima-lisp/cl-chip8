(in-package #:cl-chip8)

(defstruct (chip8-quirks (:constructor %make-chip8-quirks))
  (profile :modern :type (member :modern :cosmac-vip :octo))
  (vf-behavior :preserve :type (member :preserve :reset))
  (memory-i :preserve :type (member :preserve :increment))
  (display-wait :none :type (member :none :wait))
  (clipping :clip :type (member :clip :wrap))
  (shift-source :vx :type (member :vx :vy))
  (bnnn-register :v0 :type (member :v0 :vx))
  (fx0a-completion :press :type (member :press :release)))

(defparameter *chip8-quirk-slots*
  '((:vf-behavior . chip8-quirks-vf-behavior)
    (:memory-i . chip8-quirks-memory-i)
    (:display-wait . chip8-quirks-display-wait)
    (:clipping . chip8-quirks-clipping)
    (:shift-source . chip8-quirks-shift-source)
    (:bnnn-register . chip8-quirks-bnnn-register)
    (:fx0a-completion . chip8-quirks-fx0a-completion)))

(defparameter *chip8-quirk-defaults*
  '((:modern
     :vf-behavior :preserve
     :memory-i :preserve
     :display-wait :none
     :clipping :clip
     :shift-source :vx
     :bnnn-register :v0
     :fx0a-completion :press)
    (:cosmac-vip
     :vf-behavior :reset
     :memory-i :increment
     :display-wait :wait
     :clipping :clip
     :shift-source :vy
     :bnnn-register :v0
     :fx0a-completion :release)
    (:octo
     :vf-behavior :preserve
     :memory-i :increment
     :display-wait :none
     :clipping :wrap
     :shift-source :vy
     :bnnn-register :v0
     :fx0a-completion :release)))

(defun %chip8-quirk-defaults (profile)
  (or (cdr (assoc profile *chip8-quirk-defaults*))
      (%config-error (format nil "unknown quirk profile: ~S" profile)
                     :key :profile)))

(defun make-chip8-quirks (&key (profile :modern) vf-behavior memory-i display-wait
                                clipping shift-source bnnn-register fx0a-completion)
  (let ((defaults (%chip8-quirk-defaults profile))
        (overrides (list :vf-behavior vf-behavior
                         :memory-i memory-i
                         :display-wait display-wait
                         :clipping clipping
                         :shift-source shift-source
                         :bnnn-register bnnn-register
                         :fx0a-completion fx0a-completion)))
    (apply #'%make-chip8-quirks
           :profile profile
           (loop for entry in *chip8-quirk-slots*
                 for slot = (car entry)
                 append (list slot (or (getf overrides slot)
                                       (getf defaults slot)))))))

(defun merge-chip8-quirks (quirks &rest overrides)
  (apply #'make-chip8-quirks
         :profile (chip8-quirks-profile quirks)
         (loop for (slot . accessor) in *chip8-quirk-slots*
               append (list slot (or (getf overrides slot)
                                     (funcall accessor quirks))))))
