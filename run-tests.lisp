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

(defun configure-local-source-registry (root) (let ((sibling-root (truename (merge-pathnames #p"../" root)))) (asdf:initialize-source-registry `(:source-registry (:tree ,sibling-root) :ignore-inherited-configuration))))

(let ((root (script-directory))) (configure-local-source-registry root))
(asdf:load-system "cl-host-kit")
(asdf:test-system "cl-chip8")
(host-kit:quit 0)
