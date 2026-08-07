(in-package #:cl-chip8/test)

(describe "memory-reset!"
  (it "zeroes every byte, including one previously written directly"
    (setf (aref *memory* 100) 42)
    (memory-reset!)
    (expect (aref *memory* 100) :to-be 0)))

(describe "memory-read and memory-write (Prolog foreign predicates)"
  (it "writes a byte through the rulebase and reads the same value back"
    (memory-reset!)
    (query-prolog *rulebase* (list 'memory-write 10 200))
    (let ((solutions (query-prolog *rulebase* (list 'memory-read 10 '?value))))
      (expect (solution-binding '?value (first solutions)) :to-be 200)))
  (it "reaches the last valid address, 4095, the memory-write/memory-read boundary case"
    (memory-reset!)
    (query-prolog *rulebase* (list 'memory-write 4095 7))
    (let ((solutions (query-prolog *rulebase* (list 'memory-read 4095 '?value))))
      (expect (solution-binding '?value (first solutions)) :to-be 7)))
  (it "agrees with a direct AREF, since both paths hit the same array"
    (memory-reset!)
    (query-prolog *rulebase* (list 'memory-write 50 99))
    (expect (aref *memory* 50) :to-be 99)))

(describe "memory-read and memory-write bounds checking"
  (it "signals chip8-memory-access-out-of-bounds for memory-write one byte past the end"
    (memory-reset!)
    (signals chip8-memory-access-out-of-bounds
      (query-prolog *rulebase* (list 'memory-write 4096 1))))
  (it "signals chip8-memory-access-out-of-bounds for memory-read one byte past the end"
    (memory-reset!)
    (signals chip8-memory-access-out-of-bounds
      (query-prolog *rulebase* (list 'memory-read 4096 '?value))))
  (it "reports the offending address and span on the condition"
    (let ((condition
            (handler-case
                (progn (query-prolog *rulebase* (list 'memory-write 4096 1)) nil)
              (chip8-memory-access-out-of-bounds (c) c))))
      (expect condition :to-be-truthy)
      (when condition
        (with-soft-assertions
          (expect (chip8-memory-access-out-of-bounds-address condition) :to-be 4096)
          (expect (chip8-memory-access-out-of-bounds-span condition) :to-be 1))))))

(describe "load-bytes-into-memory"
  (it "copies bytes starting at the given address"
    (memory-reset!)
    (load-bytes-into-memory #(1 2 3) 500)
    (with-soft-assertions
      (expect (aref *memory* 500) :to-be 1)
      (expect (aref *memory* 501) :to-be 2)
      (expect (aref *memory* 502) :to-be 3)))
  (it "fits exactly when the byte count equals the available space to the end of memory"
    (memory-reset!)
    (load-bytes-into-memory
     (make-array (- +memory-size+ +rom-load-address+)
                 :element-type '(unsigned-byte 8) :initial-element 9)
     +rom-load-address+)
    (expect (aref *memory* (1- +memory-size+)) :to-be 9))
  (it "signals chip8-rom-too-large by one byte past the available space"
    (signals chip8-rom-too-large
      (load-bytes-into-memory
       (make-array (1+ (- +memory-size+ +rom-load-address+))
                   :element-type '(unsigned-byte 8) :initial-element 0)
       +rom-load-address+)))
  (it "reports the offending size and the available space on the condition"
    (let ((condition
            (handler-case
                (progn
                  (load-bytes-into-memory
                   (make-array 4000 :element-type '(unsigned-byte 8) :initial-element 0)
                   +rom-load-address+)
                  nil)
              (chip8-rom-too-large (c) c))))
      (expect condition :to-be-truthy)
      (when condition
        (with-soft-assertions
          (expect (chip8-rom-too-large-size condition) :to-be 4000)
          (expect (chip8-rom-too-large-available condition)
                  :to-be (- +memory-size+ +rom-load-address+)))))))
