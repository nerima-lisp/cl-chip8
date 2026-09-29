;;;; Shared build bootstrap and compilation-warning gate.
(require :asdf)

(defun bootstrap-script-directory (script-path)
  (make-pathname :name nil :type nil :defaults
                 (or script-path (error "Unable to determine the script location"))))

(defun bootstrap-project-root (script-path)
  (truename (merge-pathnames #p"../" (bootstrap-script-directory script-path))))

(defun local-source-directories (root)
  (let ((organization-roots
          (remove-duplicates
           (list (truename root)
                 (truename (merge-pathnames #p"../" root))
                 (truename (merge-pathnames #p"../../" root))
                 (truename (merge-pathnames #p"../../../" root)))
           :test #'equal)))
    (remove-duplicates
     (loop for organization-root in organization-roots
           append (loop for name in '("cl-chip8" "cl-tty-kit" "cl-cli"
                                      "cl-concurrent-kit" "cl-boundary-kit"
                                      "cl-date-kit" "cl-host-kit" "cl-codec-kit"
                                      "cl-weave" "cl-parser-kit" "cl-log-kit"
                                      "cl-json-kit" "cl-toml-kit"
                                      "cl-observability-kit")
                        for directory = (merge-pathnames
                                         (format nil "~A/" name) organization-root)
                        when (probe-file directory) collect (truename directory)))
     :test #'equal)))

(defun configure-local-source-registry (root)
  (unless (sb-ext:posix-getenv "CL_SOURCE_REGISTRY")
    (asdf:initialize-source-registry
     `(:source-registry
       ,@(mapcar (lambda (directory) `(:directory ,directory))
                 (local-source-directories root))
       :ignore-inherited-configuration))))

(defparameter *chip8-build-dependencies*
  '("cl-dataflow-kit" "cl-tty-kit" "cl-cli" "cl-toml-kit"
    "cl-log-kit" "cl-observability-kit" "cl-concurrent-kit"
    "cl-date-kit" "cl-host-kit" "cl-weave" "cl-json-kit"))

(defun chip8-path-prefix-p (path root)
  (let ((path (namestring (truename path)))
        (root (namestring (truename root))))
    (and (<= (length root) (length path))
         (string= root path :end2 (length root)))))

(defun load-chip8-build-dependencies ()
  (dolist (system *chip8-build-dependencies*)
    (asdf:load-system system)))

(defun run-with-compilation-warning-gate (root thunk)
  "Run THUNK and fail for warnings from this project's compile units."
  (let ((warnings '()))
    (handler-bind
        ((warning
           (lambda (condition)
             (let ((source *compile-file-truename*))
               (when (and source (chip8-path-prefix-p source root))
                 (push (list (truename source) condition) warnings)
                 (muffle-warning condition))))))
      (let ((asdf:*compile-file-warnings-behaviour* :warn)
            (asdf:*compile-file-failure-behaviour* :error))
        (funcall thunk)))
    (setf warnings (nreverse warnings))
    (format t "~&Compilation warning gate: ~D warning~:P.~%"
            (length warnings))
    (when warnings
      (dolist (entry warnings)
        (format *error-output* "~&Compilation warning: ~A: ~A~%"
                (namestring (first entry)) (second entry)))
      (error "Compilation warning gate failed with ~D project warning~:P."
             (length warnings)))))

(defun compile-chip8-systems-with-warning-gate (root &key (force t))
  (load-chip8-build-dependencies)
  (run-with-compilation-warning-gate
   root
   (lambda ()
     (asdf:operate 'asdf:compile-op "cl-chip8"
                   :force force :on-warnings :warn :on-failure :error)
     (asdf:operate 'asdf:compile-op "cl-chip8/test"
                   :force force :on-warnings :warn :on-failure :error))))
