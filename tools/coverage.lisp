;;;; tools/coverage.lisp -- force an instrumented compile before reporting.
(require :asdf)

(require :sb-cover)

(declaim (optimize (sb-cover:store-coverage-data 3)))

(defun script-directory ()
  (make-pathname
   :name
   nil
   :type
   nil
   :defaults
   (or
    *load-truename*
    *compile-file-truename*
    (error "Unable to determine the script location"))))

(defun project-root ()
  (truename (merge-pathnames #p"../" (script-directory))))

(defun local-source-directories (root)
  (let ((organization-root (truename (merge-pathnames #p"../" root))))
    (loop for name in (list
                       "cl-chip8"
                       "cl-prolog"
                       "cl-tty-kit"
                       "cl-cli"
                       "cl-concurrent-kit"
                       "cl-boundary-kit"
                       "cl-date-kit"
                       "cl-host-kit"
                       "cl-codec-kit"
                       "cl-weave")
          for directory = (merge-pathnames
                           (format nil "~A/" name)
                           organization-root)
          when (probe-file directory)
            collect (truename directory))))

(defun configure-local-source-registry (root) (asdf:initialize-source-registry `(:source-registry ,@(mapcar (lambda (directory) `(:directory ,directory)) (local-source-directories root)) :ignore-inherited-configuration)))
(let ((root (project-root))) (configure-local-source-registry root))
(asdf:load-system "cl-host-kit")

(defun configure-isolated-output-cache (directory root)
  (let ((cache-root (merge-pathnames #p"asdf-cache/" directory))
        (source-roots (local-source-directories root)))
    (ensure-directories-exist cache-root)
    (asdf:initialize-output-translations
     `(:output-translations
       ,@(loop for source-root in source-roots
               for source-name = (car (last (pathname-directory source-root)))
               for cache = (merge-pathnames
                            (format nil "~A/" source-name)
                            cache-root)
               do (ensure-directories-exist cache)
               collect `(,(merge-pathnames #p"**/*.*" source-root)
                         (,cache :implementation)))
       :ignore-inherited-configuration))))

(defun coverage-directory (root) (let ((configured (host-kit:getenv "CL_CHIP8_COVERAGE_DIR"))) (host-kit:ensure-directory-pathname (if configured (host-kit:ensure-pathname configured) (merge-pathnames #p"coverage/" root)))))

(defun coverage-excluded-source-files (root)
  (mapcar
   (lambda (name)
     (merge-pathnames (format nil "src/~A.lisp" name) root))
   (list "app"
         "cli"
         "conditions"
         "fontset"
         "memory-types"
         "state-types"
         "keypad-types"
         "opcodes"
         "package"
         "display-types"
         "render-types"
         "concurrent-render-types"
         "concurrent-render-macros")))

(let* ((root (project-root)) (directory (coverage-directory root)) (source-directory (merge-pathnames #p"src/" root)) (excluded-source-files (coverage-excluded-source-files root))) (configure-local-source-registry root) (ensure-directories-exist directory) (configure-isolated-output-cache directory root) (format t "~&Forcing instrumented compilation...~%") (asdf:load-system "cl-chip8/test" :force t) (let ((runner (find-symbol "RUN-TESTS" "CL-CHIP8/TEST"))) (unless (and runner (fboundp runner)) (error "CL-CHIP8/TEST:RUN-TESTS is unavailable")) (funcall runner :coverage t :coverage-output (merge-pathnames #p"cl-chip8.coverage" directory) :coverage-report-directory directory :coverage-include-pathnames (list source-directory) :coverage-exclude-pathnames excluded-source-files :coverage-minimum-expression 99 :coverage-minimum-branch 100)) (format t "~&Coverage report: ~A~%" (merge-pathnames #p"cover-index.html" directory)) (host-kit:quit 0))
