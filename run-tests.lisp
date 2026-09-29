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
  "Register the sibling checkout tree, unless a registry was supplied for us.

`:IGNORE-INHERITED-CONFIGURATION' is what makes a developer's run reproducible:
it pins resolution to the sibling checkouts and ignores whatever ASDF
configuration happens to be on the machine.

Under Nix it does the opposite. Each dependency is its own /nix/store path and
the builder exports CL_SOURCE_REGISTRY naming them; ../ is /build, which holds
only the unpacked source. Replacing the registry there discards the paths the
derivation provided.

So: honour an explicitly supplied registry, and otherwise behave as before.
No CL_SOURCE_REGISTRY is set for a local `sbcl --script run-tests.lisp', so
the developer path is unchanged."
  (unless (sb-ext:posix-getenv "CL_SOURCE_REGISTRY")
    (let ((sibling-root (truename (merge-pathnames #p"../" root))))
      (asdf:initialize-source-registry
       `(:source-registry (:tree ,sibling-root)
         :ignore-inherited-configuration)))))

(defun run-with-compilation-warning-gate (root thunk)
  "Run THUNK and fail on every compilation warning except src/app.lisp.

The exception is deliberately tied to this checkout's source pathname, so a
warning from any dependency or test source remains fatal.  STYLE-WARNING and
SBCL's undefined-name warnings are WARNING conditions and are therefore
covered by the same handler."
  (let ((warning-count 0)
        (app-warning-count 0)
        (app-source (truename (merge-pathnames #p"src/app.lisp" root))))
    (let ((asdf:*compile-file-warnings-behaviour* :error)
          (asdf:*compile-file-failure-behaviour* :error))
      (handler-bind
        ((warning
           (lambda (condition)
             (incf warning-count)
             (if (and *compile-file-truename*
                      (equal (truename *compile-file-truename*) app-source))
                 (progn
                   (incf app-warning-count)
                   (muffle-warning condition))
                 (error condition)))))
        (prog1 (funcall thunk)
          (format t "~&Compilation warning gate: ~D warning~:P; ~D excluded from src/app.lisp.~%"
                  warning-count
                  app-warning-count))))))

(let ((root (script-directory)))
  (configure-local-source-registry root))
(asdf:load-system "cl-host-kit")
(let ((root (script-directory)))
  (run-with-compilation-warning-gate
   root
   (lambda ()
     (asdf:test-system "cl-chip8"))))
(host-kit:quit 0)
