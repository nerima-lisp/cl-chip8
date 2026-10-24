(in-package #:cl-chip8)

(deftype render-executor ()
  '(satisfies cl-concurrent-kit:executor-p))

(deftype render-channel ()
  '(satisfies cl-concurrent-kit:channel-p))

(deftype render-semaphore ()
  'sb-thread:semaphore)

(deftype render-lock ()
  'cl-concurrent-kit:lock)

(defstruct (render-row-snapshot
            (:constructor %make-render-row-snapshot (terminal-row pixels)))
  (terminal-row 0 :type fixnum)
  (pixels (make-array '(0 0) :initial-element 0)
          :type (array * (* *))))

(defstruct (render-batch-job
            (:constructor
             %make-render-batch-job
             (snapshots results row-styles mode start end)))
  (snapshots nil :type (or null (vector t *)))
  (results nil :type (or null (vector t *)))
  (row-styles nil :type (or null (vector t *)))
  (mode :lores :type (member :lores :half-block :quarter-block :braille))
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
              parallel-threshold-supplied-p
              shutdown-timeout
              submitted-counter
              completed-counter
              serial-row-count
              lock
              closed-p
              snapshot-buffer
              result-buffer
              style-buffer
              job-buffer
              state)))
  (executor nil :type (or null render-executor))
  (jobs-channel nil :type (or null render-channel))
  (completion-semaphore nil :type (or null render-semaphore))
  (parallelism 1 :type (integer 1 *))
  (parallel-threshold 13 :type (integer 1 *))
  (parallel-threshold-supplied-p nil :type boolean)
  (shutdown-timeout nil :type (or null duration))
  submitted-counter
  completed-counter
  (serial-row-count 0 :type (unsigned-byte 64))
  (lock nil :type (or null render-lock))
  (closed-p nil :type boolean)
  (snapshot-buffer nil :type (or null (vector t *)))
  (result-buffer nil :type (or null (vector t *)))
  (style-buffer nil :type (or null (vector t *)))
  (job-buffer nil :type (or null (vector t *)))
  (state (make-chip8-render-state) :type chip8-render-state))

(defconstant +concurrent-render-minimum-snapshots+ 9 "Minimum snapshot count at the reference terminal row count.")
(defconstant +concurrent-render-default-parallel-threshold+ 13 "Default parallel threshold at the reference terminal row count.")
(defconstant +concurrent-render-reference-row-count+ 16 "Reference terminal-row count for proportional render thresholds.")
(defconstant +concurrent-render-default-parallelism+ 8 "Default number of persistent render workers.")
(defconstant +concurrent-render-rows-per-job+ 2 "Maximum dirty terminal rows assigned to one render job.")
