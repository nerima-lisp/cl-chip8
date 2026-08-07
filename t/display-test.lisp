(in-package #:cl-chip8/test)

(describe "display-reset!"
  (it "clears every pixel, including one previously written directly"
    (setf (aref *display* 0 0) 1)
    (display-reset!)
    (expect (aref *display* 0 0) :to-be 0)))

(describe "display-clear (Prolog foreign predicate)"
  (it "clears every pixel via the rulebase"
    (setf (aref *display* 5 5) 1)
    (query-prolog *rulebase* '(display-clear))
    (expect (aref *display* 5 5) :to-be 0)))

(describe "display-pixel (Prolog foreign predicate)"
  (it "reads back a pixel written directly to the array"
    (display-reset!)
    (setf (aref *display* 3 4) 1)
    (let ((solutions (query-prolog *rulebase* (list 'display-pixel 4 3 '?value))))
      (expect (solution-binding '?value (first solutions)) :to-be 1)))
  (it "reads 0 for a pixel that was never set"
    (display-reset!)
    (let ((solutions (query-prolog *rulebase* (list 'display-pixel 63 31 '?value))))
      (expect (solution-binding '?value (first solutions)) :to-be 0))))

(describe "display-xor-pixel!"
  (it "sets a clear pixel and reports no collision"
    (display-reset!)
    (with-soft-assertions
      (expect (display-xor-pixel! 2 2) :to-be-falsy)
      (expect (display-pixel-value 2 2) :to-be 1)))
  (it "clears a set pixel and reports a collision"
    (display-reset!)
    (display-xor-pixel! 2 2)
    (with-soft-assertions
      (expect (display-xor-pixel! 2 2) :to-be-truthy)
      (expect (display-pixel-value 2 2) :to-be 0))))

(describe "display-xor-pixel (Prolog foreign predicate)"
  (it "matches the Lisp-level primitive's collision report"
    (display-reset!)
    ;; First XOR sets the pixel (no collision); the second clears it (a
    ;; collision), exercising the same 1->0 transition DISPLAY-XOR-PIXEL!
    ;; reports directly.
    (query-prolog *rulebase* (list 'display-xor-pixel 1 1 '?collided))
    (let ((solutions (query-prolog *rulebase* (list 'display-xor-pixel 1 1 '?collided))))
      (expect (solution-binding '?collided (first solutions)) :to-be 1))))
