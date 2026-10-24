(in-package #:cl-chip8)

(defstruct (chip8-platform
            (:constructor %make-chip8-platform)
            (:conc-name %chip8-platform-))
  (name :modern :type keyword)
  (memory-size +memory-size+ :type (member 4096 65536))
  (resolutions '(:lores) :type list)
  (font-sets '(:chip8) :type list)
  (default-tickrate 12 :type (integer 1 *))
  (default-quirks (make-chip8-quirks) :type chip8-quirks))

(defun chip8-platform-name (platform)
  (%chip8-platform-name platform))

(defun chip8-platform-memory-size (platform)
  (%chip8-platform-memory-size platform))

(defun chip8-platform-resolutions (platform)
  (copy-list (%chip8-platform-resolutions platform)))

(defun chip8-platform-font-sets (platform)
  (copy-list (%chip8-platform-font-sets platform)))

(defun chip8-platform-default-tickrate (platform)
  (%chip8-platform-default-tickrate platform))

(defun chip8-platform-default-quirks (platform)
  (merge-chip8-quirks (%chip8-platform-default-quirks platform)))

(defparameter *chip8-platforms*
  (list
   (%make-chip8-platform
    :name :cosmac-vip
    :memory-size 4096
    :resolutions '(:lores)
    :font-sets '(:chip8)
    :default-tickrate 15
    :default-quirks (make-chip8-quirks :profile :cosmac-vip))
   (%make-chip8-platform
    :name :modern
    :memory-size 4096
    :resolutions '(:lores)
    :font-sets '(:chip8)
    :default-tickrate 12
    :default-quirks (make-chip8-quirks :profile :modern))
   (%make-chip8-platform
    :name :schip
    :memory-size 4096
    :resolutions '(:lores :hires)
    :font-sets '(:chip8 :schip-large)
    :default-tickrate 30
    :default-quirks (make-chip8-quirks :profile :modern))
   (%make-chip8-platform
    :name :schip-legacy
    :memory-size 4096
    :resolutions '(:lores :hires)
    :font-sets '(:chip8 :schip-large)
    :default-tickrate 30
    :default-quirks (make-chip8-quirks :profile :modern))
   (%make-chip8-platform
    :name :xo-chip
    :memory-size 65536
    :resolutions '(:lores :hires)
    :font-sets '(:chip8 :schip-large)
    :default-tickrate 100
    :default-quirks (make-chip8-quirks :profile :modern))))

(defun find-chip8-platform (name)
  (etypecase name
    (keyword
     (find name *chip8-platforms* :key #'%chip8-platform-name :test #'eq))
    (string
     (find name *chip8-platforms*
           :key (lambda (platform)
                  (symbol-name (%chip8-platform-name platform)))
           :test #'string-equal))))

