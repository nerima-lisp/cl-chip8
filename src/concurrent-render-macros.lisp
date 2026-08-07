;;;; src/concurrent-render-macros.lisp -- rendering pipeline convenience macros.
(in-package #:cl-chip8)

(defmacro with-chip8-render-pipeline ((pipeline &rest initargs) &body body)
  "Run BODY with a bounded concurrent rendering pipeline."
  `(let ((,pipeline (make-chip8-render-pipeline ,@initargs)))
     (unwind-protect (locally
                       ,@body)
       (close-chip8-render-pipeline ,pipeline))))
