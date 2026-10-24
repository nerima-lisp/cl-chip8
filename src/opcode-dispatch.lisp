(in-package #:cl-chip8)

(defun fetch-opcode (machine &optional (pc (chip8-machine-pc machine)))
  (check-memory-access machine pc 2)
  (logior (ash (memory-read machine pc) 8)
          (memory-read machine (1+ pc))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %opcode-body (definition)
    (let ((bindings (getf definition :fields)))
      `(let* ,bindings ,@(getf definition :body))))

  (defun %opcode-family (definition)
    (ldb (byte 4 12) (getf definition :pattern)))

  (defun %opcode-subkey (definition family)
    (let ((pattern (getf definition :pattern)))
      (case family
        (0 (if (= (getf definition :mask) #xffff) pattern :otherwise))
        (8 (ldb (byte 4 0) pattern))
        ((5 9) (ldb (byte 4 0) pattern))
        ((14 15) (ldb (byte 8 0) pattern))
        (otherwise nil)))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %opcode-case-key (family)
    (case family
      (0 'opcode)
      (8 '(ldb (byte 4 0) opcode))
      ((5 9) '(ldb (byte 4 0) opcode))
      (otherwise '(ldb (byte 8 0) opcode))))

  (defun %opcode-family-form (family definitions)
    (let* ((members (remove-if-not
                     (lambda (entry)
                       (= (%opcode-family entry) family))
                     definitions))
           (sys (find 'sys members :key (lambda (entry) (getf entry :name)))))
      `(,family
        ,(if (= family 0)
             `(case opcode
                ,@(mapcar
                   (lambda (entry)
                     `(,(getf entry :pattern)
                       ,(%opcode-body entry)))
                   (remove-if-not
                    (lambda (entry)
                      (= (getf entry :mask) #xffff))
                    members))
                (otherwise
                 (cond
                  ,@(mapcar
                     (lambda (entry)
                       `((= (logand opcode ,(getf entry :mask))
                            ,(getf entry :pattern))
                         ,(%opcode-body entry)))
                     (remove-if
                      (lambda (entry)
                        (or (eq (getf entry :name) 'sys)
                            (= (getf entry :mask) #xffff)))
                      members))
                  (t ,(%opcode-body sys)))))
           (if (member family '(5 8 9 14 15))
               `(case ,(%opcode-case-key family)
                  ,@(mapcar
                     (lambda (entry)
                       `(,(%opcode-subkey entry family)
                         ,(%opcode-body entry)))
                     (remove-if
                      (lambda (entry)
                        (eq (%opcode-subkey entry family) :otherwise))
                      members))
                  (otherwise (error 'chip8-invalid-opcode :opcode opcode)))
             (%opcode-body (first members))))))
    ))

(defmacro define-chip8-dispatch ()
  (let* ((definitions (reverse *chip8-opcode-definitions*))
         (families (remove-duplicates (mapcar #'%opcode-family definitions)))
         (family-forms (mapcar (lambda (family)
                                 (%opcode-family-form family definitions))
                               families)))
    `(defun execute-instruction! (machine)
       (when (or (chip8-machine-halted-p machine)
                 (chip8-wait-state-kind (chip8-machine-waiting machine)))
         (return-from execute-instruction! machine))
       (let* ((opcode (fetch-opcode machine))
              (family (ldb (byte 4 12) opcode)))
         (incf (chip8-machine-instructions machine))
         (case family
           ,@family-forms
           (otherwise (error 'chip8-invalid-opcode :opcode opcode))))
       machine)))

(define-chip8-dispatch)
