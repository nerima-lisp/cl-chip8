(in-package #:cl-chip8)

(defstruct (render-row-snapshot
            (:constructor
             %make-render-row-snapshot
             (terminal-row
              top-pixels
              bottom-pixels
              top-generation
              bottom-generation))) terminal-row
  top-pixels
  bottom-pixels
  top-generation
  bottom-generation)

(defstruct (render-batch-job
            (:constructor
             %make-render-batch-job
             (snapshots results start end)))
  snapshots
  results
  (start 0 :type fixnum)
  (end 0 :type fixnum)
  caught-condition)

(defstruct (chip8-render-pipeline
            (:constructor
             %make-chip8-render-pipeline
             (executor
              jobs-channel
              completion-semaphore
              parallelism
              parallel-threshold
              shutdown-timeout
              submitted-counter
              completed-counter
              serial-row-count
              lock
              closed-p
              snapshot-buffer
              result-buffer
              job-buffer)))
  executor
  jobs-channel
  completion-semaphore
  (parallelism 1 :type (integer 1 *))
  (parallel-threshold 13 :type (integer 1 *))
  shutdown-timeout
  submitted-counter
  completed-counter
  (serial-row-count 0 :type (unsigned-byte 64))
  lock
  (closed-p nil :type boolean)
  snapshot-buffer
  result-buffer
  job-buffer)

(defconstant +concurrent-render-minimum-snapshots+ 9 "Minimum partial batch that splits into multiple persistent CCK jobs.")
