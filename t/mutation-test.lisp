(in-package #:cl-chip8/test)

(defun opcode-definition (name)
  (find name cl-chip8::*chip8-opcode-definitions*
        :key (lambda (definition) (getf definition :name))
        :test (lambda (requested actual)
                (string= (symbol-name requested) (symbol-name actual)))))

(defun opcode-definition-lambda (name)
  (let ((definition (opcode-definition name)))
    (unless definition
      (error "No opcode definition for ~S." name))
    `(lambda (cl-chip8::machine cl-chip8::opcode)
       (let* ,(getf definition :fields)
         ,@(getf definition :body)))))

(defun chip8-quirk-mutations (form path)
  (declare (ignore path))
  (when (consp form)
    (case (first form)
      (cl-chip8::%shift-source
       (list `(cl-chip8:chip8-machine-register
                cl-chip8::machine cl-chip8::x)
             `(cl-chip8:chip8-machine-register
                cl-chip8::machine cl-chip8::y)))
      (cl-chip8::%vf-reset-if-needed
       (list '(progn)))
      ((cl-chip8::%draw-sprite! cl-chip8::%store-registers!
        cl-chip8::%load-registers!)
       (list '(progn))))))

(cl-weave::register-mutation-operator
 :chip8-quirk-branch
 #'chip8-quirk-mutations)

(defun opcode-mutation-results (name)
  (let ((form (opcode-definition-lambda name)))
    (cl-weave:run-mutations
     form
     (lambda (mutated-form mutation)
       (declare (ignore mutation))
       (handler-case
           (progn
             (dolist (case *opcode-semantic-cases*)
             (when (string= (symbol-name (second case))
                              (symbol-name name))
                 (assert-semantic-case case (eval mutated-form))))
             t)
         (cl-weave:assertion-failure () nil)))
     :operators '(:arithmetic-operator :comparison-operator
                  :boolean-literal :conditional-branch
                  :chip8-quirk-branch))))

(defun assert-opcode-mutation-score (name)
  (let* ((results (opcode-mutation-results name))
         (summary (cl-weave:mutation-summary results)))
    (format t "Mutation ~A: ~S~%" name summary)
    (dolist (result results)
      (when (eq (cl-weave:mutation-result-status result) :errored)
        (format t "  errored ~S: ~A~%"
                (cl-weave:mutation-form (cl-weave:mutation-result-mutation result))
                (cl-weave:mutation-result-condition result))))
    (cl-weave:assert-mutation-score results 1.0)))

(describe "mutation quality gates"
  (it-each
      ((:add-register) (:sub-register) (:subn-register) (:shr) (:or)
       (:se-byte) (:jp-v0) (:draw) (:store-registers) (:load-registers))
    "kills mutations in the real ~A opcode body" (name)
    (assert-opcode-mutation-score name)))
