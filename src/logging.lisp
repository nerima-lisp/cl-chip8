;;;; Structured logging boundary for the CHIP-8 application.

(in-package #:cl-chip8)

(defvar *chip8-logger* nil)

(defun %chip8-package-function (package-name function-name)
  (let* ((package (find-package package-name))
         (symbol (and package (find-symbol function-name package))))
    (unless (and symbol (fboundp symbol))
      (error "Required ~A::~A entry point is unavailable."
             package-name function-name))
    (symbol-function symbol)))

(defun %chip8-log-kit-function (name)
  (%chip8-package-function "LOG-KIT" name))

(defun %chip8-log-kit-level (name)
  (let* ((package (find-package "LOG-KIT"))
         (symbol (and package (find-symbol name package))))
    (unless (and symbol (boundp symbol))
      (error "Required LOG-KIT::~A level is unavailable." name))
    (symbol-value symbol)))

(defun make-chip8-logger (&key path (name "cl-chip8") (level 0))
  "Make a JSON logger which writes only to PATH, or discards records.

PATH is deliberately the only output boundary.  A NIL PATH uses cl-log-kit's
null handler and therefore never writes to *STANDARD-OUTPUT*."
  (let ((stream nil) (handler nil) (logger nil))
    (unwind-protect
         (progn
           (setf handler
                 (if path
                     (progn
                       (setf stream (open path :direction :output :if-exists :append
                                          :if-does-not-exist :create))
                       (funcall (%chip8-log-kit-function "MAKE-JSON-HANDLER")
                                :stream stream :auto-flush t :owns-stream t))
                     (funcall (%chip8-log-kit-function "MAKE-NULL-HANDLER"))))
           (setf logger
                 (funcall (%chip8-log-kit-function "MAKE-LOGGER")
                          :name name :handler handler :level level))
           logger)
      (unless logger
        (when handler
          (ignore-errors
            (funcall (%chip8-log-kit-function "CLOSE-HANDLER") handler)))
        (when (and stream (open-stream-p stream))
          (ignore-errors (close stream)))))))

(defun close-chip8-logger (logger)
  (when logger
    (funcall (%chip8-log-kit-function "CLOSE-HANDLER")
             (funcall (%chip8-log-kit-function "LOGGER-HANDLER") logger)))
  nil)

(defun chip8-log (logger level message &optional fields)
  "Emit one structured record through LOGGER, when LOGGER is non-NIL."
  (when logger
    (funcall (%chip8-log-kit-function "EMIT-LOG") logger level message fields)))

(defun chip8-log-info (logger message &optional fields)
  (chip8-log logger (%chip8-log-kit-level "+LEVEL-INFO+") message fields))

(defun chip8-log-error (logger message &optional fields)
  (chip8-log logger (%chip8-log-kit-level "+LEVEL-ERROR+") message fields))

(defun flush-chip8-logger (logger)
  (when logger
    (funcall (%chip8-log-kit-function "FLUSH-LOGGER") logger))
  logger)
