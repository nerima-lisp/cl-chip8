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

(let ((root (script-directory)))
  (configure-local-source-registry root))
(asdf:load-system "cl-host-kit")
(asdf:test-system "cl-chip8")
(host-kit:quit 0)
