;;;; src/display-types.lisp -- framebuffer storage and synchronization data.
(in-package #:cl-chip8)

(defconstant +display-width+ 64
  "The framebuffer's width in pixels.")

(defconstant +display-height+ 32
  "The framebuffer's height in pixels.")

(defconstant +display-terminal-row-count+ (truncate +display-height+ 2)
  "The number of terminal rows represented by the framebuffer.")

(deftype display-column () '(integer 0 63))
(deftype display-row () '(integer 0 31))
(deftype display-terminal-row () '(integer 0 15))
(deftype display-row-bits () '(simple-array bit (64)))
(deftype display-dirty-rows () '(simple-array bit (32)))
(deftype display-framebuffer () '(simple-array bit (32 64)))
(deftype display-row-generations ()
  '(simple-array (unsigned-byte 64) (32)))

(defvar *display* (make-array
                   (list +display-height+ +display-width+)
                   :element-type
                   'bit
                   :initial-element
                   0)
  "The 64x32 monochrome framebuffer, indexed as (ROW COLUMN).")

(defvar *display-dirty-rows* (make-array +display-height+ :element-type 'bit :initial-element 1)
  "Pixel rows that changed since the last concurrent render commit.")

(defvar *display-dirty-terminal-row-count* +display-terminal-row-count+
  "Number of terminal rows with at least one dirty pixel row.")

(defvar *display-row-generations*
  (make-array +display-height+
              :element-type '(unsigned-byte 64)
              :initial-element 0)
  "Generation counters for source rows used by concurrent render commits.")

(check-type *display* display-framebuffer)
(check-type *display-dirty-rows* display-dirty-rows)
(check-type *display-dirty-terminal-row-count* (integer 0 16))
(check-type *display-row-generations* display-row-generations)

(declaim (type display-framebuffer *display*)
         (type display-dirty-rows *display-dirty-rows*)
         (type (integer 0 16)
               *display-dirty-terminal-row-count*)
         (type display-row-generations *display-row-generations*))

(defvar *display-lock* (make-lock :name "cl-chip8 display")
  "Serializes framebuffer snapshots and mutations.")

(defmacro with-display-lock (&body body)
  `(with-lock-held (*display-lock*) ,@body))
