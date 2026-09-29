;;;; Lisp-level test entry point. Registers the checkout tree with ASDF and
;;;; runs the test system.

(require :asdf)

(let* ((script-path *load-truename*)
       (project-root (truename (uiop:pathname-directory-pathname script-path)))
       (bootstrap (merge-pathnames #p"tools/bootstrap.lisp" project-root)))
  (load bootstrap)
  (configure-local-source-registry project-root)
  (sb-ext:with-timeout 600
    (compile-chip8-systems-with-warning-gate project-root)
    (asdf:load-system "cl-host-kit")
    (asdf:load-system "cl-weave")
    (let ((timeout-symbol (find-symbol "*DEFAULT-TIMEOUT-MS*" "CL-WEAVE")))
      (unless timeout-symbol
        (error "cl-weave does not export *DEFAULT-TIMEOUT-MS*"))
      (setf (symbol-value timeout-symbol) 600000))
    (asdf:test-system "cl-chip8")))
(host-kit:quit 0)
