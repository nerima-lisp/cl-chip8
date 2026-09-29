;;;; Common source-tree bootstrap for local diagnostic scripts.
(defun bootstrap-script-directory (script-path)
  (make-pathname :name nil
                 :type nil
                 :defaults (or script-path
                               (error "Unable to determine the script location"))))

(defun bootstrap-project-root (script-path)
  (truename (merge-pathnames #p"../"
                             (bootstrap-script-directory script-path))))

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
           append (loop for name in (list
                                    "cl-chip8"
                                    "cl-prolog-kit"
                                    "cl-tty-kit"
                                    "cl-cli"
                                    "cl-concurrent-kit"
                                    "cl-boundary-kit"
                                    "cl-date-kit"
                                    "cl-host-kit"
                                    "cl-codec-kit"
                                    "cl-weave"
                                    "cl-parser-kit"
                                    "cl-dataflow-kit"
                                    "cl-log-kit"
                                    "cl-toml-kit"
                                    "cl-observability-kit")
                        for directory = (merge-pathnames
                                         (format nil "~A/" name)
                                         organization-root)
                        when (probe-file directory)
                          collect (truename directory)))
     :test #'equal)))

(defun configure-local-source-registry (root)
  (asdf:initialize-source-registry
   `(:source-registry
     ,@(mapcar (lambda (directory) `(:directory ,directory))
               (local-source-directories root))
     :ignore-inherited-configuration)))
