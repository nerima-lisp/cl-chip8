;;;; run-tests.lisp
;;;;
;;;; Lisp-level test entry point:
;;;;
;;;;     sbcl --script run-tests.lisp
;;;;
;;;; Registers this checkout on ASDF's source registry, inherits the caller's
;;;; configuration for the sibling dependencies (cl-prolog, cl-tty-kit,
;;;; cl-cli, cl-weave -- set CL_SOURCE_REGISTRY to the nerima-lisp checkout
;;;; root so ASDF can find them), and runs the test system. See
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
  (asdf:initialize-source-registry
   `(:source-registry
     (:tree ,root)
     :inherit-configuration)))

(let ((root (script-directory)))
  (configure-local-source-registry root)
  (asdf:test-system "cl-chip8")
  (uiop:quit 0))
