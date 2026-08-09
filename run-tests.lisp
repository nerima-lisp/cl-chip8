;;;; run-tests.lisp
;;;;
;;;; Lisp-level test entry point:
;;;;
;;;;     sbcl --script run-tests.lisp
;;;;
;;;; Registers the nerima-lisp checkout tree on ASDF's source registry and
;;;; ignores inherited configuration, so sibling dependencies resolve from
;;;; the same local checkout in every invocation. It then runs the test
;;;; system. See
;;;; PACKAGE_STANDARD.md.
;;;;
;;;; A bare `sbcl --script`, never `--non-interactive --script`: SBCL acts on
;;;; --non-interactive and exits before --script loads the file, so the command
;;;; produces no output and returns 0 -- a test step that always passes.

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
only the unpacked source. Replacing the registry there discards exactly the
paths the derivation provided, and the run fails with `Component ... not
found' for a dependency that was present the whole time -- which is how this
was found, after three correct-but-insufficient dependency declarations.

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
