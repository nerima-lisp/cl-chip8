(defpackage #:cl-chip8/test
  (:use #:cl #:cl-chip8)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it #:it-each #:expect #:signals #:run-all
                #:with-soft-assertions #:before-each #:skip
                #:benchmark #:minimum-ms
                #:collect-test-plan #:root-suite
                #:test-plan-entry-path #:test-plan-entry-status)
  (:import-from #:cl-cli
                #:parse-argv #:run-app #:option-value #:positional-value
                #:cli-invalid-option-value)
  (:export #:run-tests))
(in-package #:cl-chip8/test)
(defvar *run-example-cursor* nil)
(defvar *run-example-index* 0)
(before-each
  (when *run-example-cursor*
    (let ((entry (pop *run-example-cursor*)))
      (format *standard-output*
              "~&Plan estimate #~D (may not be the example currently running; order/retries can differ): ~S~%"
              (incf *run-example-index*)
              (test-plan-entry-path entry))
      (finish-output *standard-output*))))
(defun run-tests (&rest args)
  (let* ((lock (merge-pathnames #p".timendus.snapshots.lock"
                                (truename #p"t/")))
         (lock-existed (probe-file lock))
         (*run-example-cursor*
           (when (null args)
             (remove-if-not
              (lambda (entry)
                (eq (test-plan-entry-status entry) :run))
              (collect-test-plan
               (root-suite)
               :name-filter cl-weave:*test-name-filter*))))
         (*run-example-index* 0))
    (unwind-protect
         (let ((cl-weave:*snapshot-directory* (truename #p"t/"))
               (cl-weave:*snapshot-file-name* "timendus.snapshots"))
           (unless (apply (function run-all)
                          :reporter :spec
                          :pass-with-no-tests nil
                          args)
             (error "cl-chip8 test suite failed")))
      (when (and (not lock-existed) (probe-file lock))
        (delete-file lock))))
  t)
