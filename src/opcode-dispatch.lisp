(in-package #:cl-chip8)

(declaim (inline fetch-opcode advance-pc! dispatch-chip8-opcode))
(defun fetch-opcode (machine)
  (let ((pc (chip8-machine-pc machine)))
    (check-memory-access pc 2)
    (logior (ash (memory-read machine pc) 8)
            (memory-read machine (1+ pc)))))
(defun advance-pc! (machine &optional (amount 2))
  (setf (chip8-machine-pc machine)
        (mod (+ (chip8-machine-pc machine) amount) +memory-size+)))
(defmacro define-chip8-dispatch ()
  ;; DEFINE-CHIP8-OPCODE prepends for cheap loading; restore declaration
  ;; order so exact 00E0/00EE clauses precede the SYS family fallback.
  (let ((definitions (mapcar #'symbol-value
                             (reverse *chip8-opcode-definitions*))))
    `(defun dispatch-chip8-opcode (machine opcode family x y n kk nnn)
       (declare (type chip8-opcode opcode))
       (cond
         ,@(mapcar (lambda (definition)
                     `((= (logand opcode ,(getf definition :mask))
                          ,(getf definition :pattern))
                       (,(getf definition :handler)
                        machine family x y n kk nnn)))
                   definitions)
         (t (error 'chip8-invalid-opcode :opcode opcode))))))
