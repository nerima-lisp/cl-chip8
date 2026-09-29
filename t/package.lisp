(defpackage #:cl-chip8/test
  (:use #:cl #:cl-chip8)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:it #:it-each #:expect #:signals #:run-all #:with-soft-assertions #:before-each #:skip #:benchmark #:minimum-ms)
  (:import-from #:cl-cli
                #:parse-argv #:run-app #:option-value #:positional-value
                #:cli-invalid-option-value)
  (:export #:run-tests))
(in-package #:cl-chip8/test)
(defun run-tests (&rest args)
  (let* ((lock (merge-pathnames #p".timendus.snapshots.lock"
                                (truename #p"t/")))
         (lock-existed (probe-file lock)))
    (unwind-protect
         (let ((cl-weave:*snapshot-directory* (truename #p"t/"))
               (cl-weave:*snapshot-file-name* "timendus.snapshots"))
           (unless (apply #'run-all
                          :reporter :spec
                          :pass-with-no-tests nil
                          args)
             (error "cl-chip8 test suite failed")))
      (when (and (not lock-existed) (probe-file lock))
        (delete-file lock))))
  t)
