;;;; Lisp-level test entry point. Registers the checkout tree with ASDF and
;;;; runs the test system.
(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(defun configure-local-source-registry (root)
  (unless (sb-ext:posix-getenv "CL_SOURCE_REGISTRY")
    (let ((sibling-root (truename (merge-pathnames #p"../" root))))
      (asdf:initialize-source-registry
       `(:source-registry (:tree ,sibling-root)
         :ignore-inherited-configuration)))))

(let ((root (script-directory)))
  (configure-local-source-registry root)
  (load (merge-pathnames #p"tools/bootstrap.lisp" root))
  (compile-chip8-systems-with-warning-gate root)
  (asdf:test-system "cl-chip8"))
(host-kit:quit 0)
