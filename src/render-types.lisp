;;;; src/render-types.lisp -- terminal rendering constants and lookup data.
(in-package #:cl-chip8)

(defconstant +screen-width+ (+ +display-width+ 2)
  "Terminal screen width: the 64-pixel-wide playfield plus a 1-cell border on
each side.")

(defconstant +screen-height+ (+ (truncate +display-height+ 2) 2)
  "Terminal screen height: the 32-pixel-tall playfield, two pixel rows per
terminal row, plus a 1-cell border on each side.")

(defparameter +playfield-origin-x+ 1
  "The terminal column the playfield's leftmost pixel column renders at.")

(defparameter +playfield-origin-y+ 1
  "The terminal row the playfield's topmost pixel-pair renders at.")

(defparameter +half-block-character-table+
  (vector #\Space
          (code-char #x2584)
          (code-char #x2580)
          (code-char #x2588))
  "Character lookup for the four two-pixel terminal cells.")
