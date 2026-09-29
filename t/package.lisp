(defpackage #:cl-chip8/test
  (:use #:cl #:cl-chip8)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:it #:expect #:signals #:run-all #:with-soft-assertions #:before-each #:skip)
  (:export #:run-tests))
(in-package #:cl-chip8/test)
(defun run-tests (&rest args) (declare (ignore args)) (unless (run-all :reporter :spec :pass-with-no-tests nil) (error "cl-chip8 test suite failed")) t)
