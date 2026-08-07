;;;; src/display-types.lisp -- framebuffer storage and synchronization data.
(in-package #:cl-chip8)

(defconstant +display-width+ 64
  "The framebuffer's width in pixels.")

(defconstant +display-height+ 32
  "The framebuffer's height in pixels.")

(defvar *display* (make-array
                   (list +display-height+ +display-width+)
                   :element-type
                   'bit
                   :initial-element
                   0)
  "The 64x32 monochrome framebuffer, indexed (ROW COLUMN) i.e. (Y X) --
row-major order matches how a later stage blits this to a terminal screen. A
DEFVAR, not a DEFPARAMETER: reloading this file must not silently wipe the
screen. Call DISPLAY-RESET! to clear it explicitly.")

(defvar *display-dirty-rows* (make-array +display-height+ :element-type 'bit :initial-element 1)
  "Pixel rows that changed since the last concurrent render commit.")

(defvar *display-dirty-terminal-row-count* (truncate +display-height+ 2)
  "Number of terminal rows with at least one dirty pixel row.")

(defvar *display-row-generations* (make-array +display-height+ :initial-element 0)
  "Generation counters for source rows used by concurrent render commits.")

(defvar *display-lock* (make-lock :name "cl-chip8 display")
  "Serializes framebuffer snapshots and mutations.")

(defmacro with-display-lock (&body body)
  `(with-lock-held (*display-lock*) ,@body))
