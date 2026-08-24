(in-package #:cl-chip8)

(deftype render-executor ()
  '(satisfies cl-concurrent-kit:executor-p))

(deftype render-channel ()
  '(satisfies cl-concurrent-kit:channel-p))

(deftype render-semaphore ()
  'sb-thread:semaphore)

(deftype render-lock ()
  'lock)

(defstruct (render-row-snapshot
            (:constructor
             %make-render-row-snapshot
             (terminal-row
              top-pixels
              bottom-pixels
              top-generation
              bottom-generation)))
  (terminal-row 0 :type display-terminal-row)
  (top-pixels (make-array +display-width+ :element-type 'bit)
              :type display-row-bits)
  (bottom-pixels (make-array +display-width+ :element-type 'bit)
                 :type display-row-bits)
  (top-generation 0 :type (unsigned-byte 64))
  (bottom-generation 0 :type (unsigned-byte 64)))

(defstruct (render-batch-job
            (:constructor
             %make-render-batch-job
             (snapshots results start end)))
  (snapshots nil :type (or null (vector t *)))
  (results nil :type (or null (vector t *)))
  (start 0 :type fixnum)
  (end 0 :type fixnum)
  (caught-condition nil :type (or null condition)))

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
  (executor nil :type (or null render-executor))
  (jobs-channel nil :type (or null render-channel))
  (completion-semaphore nil :type (or null render-semaphore))
  (parallelism 1 :type (integer 1 *))
  (parallel-threshold 13 :type (integer 1 *))
  (shutdown-timeout nil :type (or null duration))
  submitted-counter
  completed-counter
  (serial-row-count 0 :type (unsigned-byte 64))
  (lock nil :type (or null render-lock))
  (closed-p nil :type boolean)
  (snapshot-buffer nil :type (or null (vector t 16)))
  (result-buffer nil :type (or null (vector t 16)))
  (job-buffer nil :type (or null (vector t *))))

(defconstant +concurrent-render-minimum-snapshots+ 9 "Minimum partial batch that splits into multiple persistent CCK jobs.")
(defconstant +concurrent-render-default-parallelism+ 8 "Default number of persistent render workers.")
(defconstant +concurrent-render-rows-per-job+ 2 "Maximum dirty terminal rows assigned to one render job.")
