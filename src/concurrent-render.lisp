;;;; src/concurrent-render.lisp -- bounded, pure row rendering with a serial
;;;; terminal-screen commit boundary.
(in-package #:cl-chip8)

(defun %start-render-workers
    (executor jobs-channel ready-channel parallelism shutdown-timeout worker)
  "Start WORKER tasks and wait for each task to announce readiness.
On startup failure, close the channels and use the native executor shutdown
timeout before propagating the original condition."
  (declare (type render-executor executor)
           (type render-channel jobs-channel ready-channel)
           (type (integer 1 *) parallelism)
           (type duration shutdown-timeout)
           (type function worker))
  (handler-case
      (progn
        (loop repeat parallelism do (submit executor worker))
        (loop repeat parallelism
              do (multiple-value-bind (ready received-p)
                     (recv ready-channel :timeout shutdown-timeout)
                   (declare (ignore ready))
                   (unless received-p
                     (error
                      "Render worker readiness channel closed before startup completed.")))))
    (error (condition)
      (close-channel ready-channel)
      (close-channel jobs-channel)
      (shutdown-executor
       executor
       :wait
       t
       :cancel-pending
       t
       :timeout
       shutdown-timeout)
      (error condition))))

(defun %make-render-snapshot-buffer ()
  "Allocate the reusable row-snapshot buffer for a render pipeline."
  (let* ((row-count +display-terminal-row-count+)
         (buffer (make-array row-count
                             :element-type t
                             :initial-element nil
                             :fill-pointer row-count)))
    (declare (type (integer 1 16) row-count)
             (type (vector t 16) buffer))
    (dotimes (index row-count buffer)
      (setf (aref buffer index)
            (%make-render-row-snapshot
             0
             (make-array +display-width+ :element-type 'bit)
             (make-array +display-width+ :element-type 'bit)
             0
             0)))))

(defun %make-render-result-buffer ()
  "Allocate the reusable string buffer for rendered rows."
  (let* ((row-count +display-terminal-row-count+)
         (buffer (make-array row-count
                             :element-type t
                             :initial-element nil
                             :fill-pointer row-count)))
    (declare (type (integer 1 16) row-count)
             (type (vector t 16) buffer))
    (dotimes (index row-count buffer)
      (setf (aref buffer index)
            (make-string +display-width+)))))

(defun %make-render-job-buffer (parallelism)
  "Allocate reusable batch-job records for PARALLELISM workers."
  (declare (type (integer 1 *) parallelism))
  (let ((buffer (make-array parallelism
                            :element-type t
                            :initial-element nil)))
    (dotimes (index parallelism buffer)
      (setf (aref buffer index)
            (%make-render-batch-job nil nil 0 0)))))

(defun %render-batch-job (job pipeline)
  "Render the rows assigned to JOB and signal its completion."
  (declare (type render-batch-job job)
           (type chip8-render-pipeline pipeline))
  (let* ((snapshots (render-batch-job-snapshots job))
         (results (render-batch-job-results job))
         (start (render-batch-job-start job))
         (end (render-batch-job-end job))
         (completed 0)
         (caught-condition nil))
    (declare (type (vector t *) snapshots results)
             (type fixnum start end completed))
    (handler-case
        (loop for snapshot-index from start below end
              do (let ((snapshot
                         (the render-row-snapshot
                              (aref snapshots snapshot-index)))
                       (reusable-characters
                         (the (or null string)
                              (aref results snapshot-index))))
                   (declare (type fixnum snapshot-index)
                            (type render-row-snapshot snapshot)
                            (type (or null string) reusable-characters))
                   (setf (aref results snapshot-index)
                         (prog1
                             (%render-row-snapshot
                              snapshot
                              reusable-characters)
                           (incf completed)))))
      (error (condition)
        (setf caught-condition condition)))
    (setf (render-batch-job-caught-condition job) caught-condition)
    (atomic-counter-incf
     (chip8-render-pipeline-completed-counter pipeline)
     completed)
    (signal-semaphore
     (chip8-render-pipeline-completion-semaphore pipeline))))

(defun %render-worker-loop (jobs-channel ready-channel pipeline)
  "Announce readiness, then render jobs until the job channel closes."
  (declare (type render-channel jobs-channel ready-channel)
           (type chip8-render-pipeline pipeline))
  (send ready-channel t)
  (loop
    (multiple-value-bind (job received-p) (recv jobs-channel)
      (unless received-p (return))
      (%render-batch-job job pipeline))))

(defun make-chip8-render-pipeline
    (&key
      ;; Keep defaulting in the body so an explicitly supplied NIL reaches
      ;; the same type check as every other invalid value.
      (parallelism (values) parallelism-supplied-p)
      (parallel-threshold (values) parallel-threshold-supplied-p)
      (shutdown-timeout (duration-of-seconds 1)))
  "Create a persistent bounded executor for terminal-row rendering.
The pipeline snapshots rows on the caller thread, maps pure conversions
over immutable row batches through persistent channel workers, and writes
each worker-owned result range into a caller-owned vector. Reusable snapshot,
result-string, and batch storage is owned by the pipeline and is not
mutated until all jobs from the current render have completed.
Completion is reported through a reusable semaphore so the hot path does not
allocate or shuttle one result payload through a second channel.
SHUTDOWN-TIMEOUT is passed directly to the native cl-concurrent-kit
executor shutdown operation."

  (unless parallelism-supplied-p
    (setf parallelism +concurrent-render-default-parallelism+))
  (unless parallel-threshold-supplied-p
    (setf parallel-threshold 13))
  (check-type parallelism (integer 1 *))
  (check-type parallel-threshold (integer 1 *))
  (check-type shutdown-timeout duration)
  (let* ((executor
           (make-executor
            :size parallelism
            :name "cl-chip8 render"
            :queue-capacity (* 2 parallelism)))
         (jobs-channel (make-channel :buffer-size parallelism))
         (completion-semaphore (make-semaphore
                                :name "cl-chip8 render completions"))
         (ready-channel (make-channel :buffer-size parallelism))
         (snapshot-buffer (%make-render-snapshot-buffer))
         (result-buffer (%make-render-result-buffer))
         (job-buffer (%make-render-job-buffer parallelism))
         (pipeline
           (%make-chip8-render-pipeline
            executor
            jobs-channel
            completion-semaphore
            parallelism
            parallel-threshold
            shutdown-timeout
            (make-atomic-counter)
            (make-atomic-counter)
            0
            (make-lock :name "cl-chip8 render pipeline")
            nil
            snapshot-buffer
            result-buffer
            job-buffer)))
    (%start-render-workers
     executor
     jobs-channel
     ready-channel
     parallelism
     shutdown-timeout
     (lambda ()
       (%render-worker-loop jobs-channel ready-channel pipeline)))
    (close-channel ready-channel)
    pipeline))

(defun close-chip8-render-pipeline
    (pipeline
     &key
       (timeout (chip8-render-pipeline-shutdown-timeout pipeline)))
  "Stop PIPELINE workers and return PIPELINE.
TIMEOUT is passed directly to cl-concurrent-kit native executor shutdown.
Closing is idempotent and serialized with rendering."
  (check-type pipeline chip8-render-pipeline)
  (check-type timeout duration)
  (with-lock-held
      ((chip8-render-pipeline-lock pipeline))
    (unless (chip8-render-pipeline-closed-p pipeline)
      (setf (chip8-render-pipeline-closed-p pipeline) t)
      (close-channel (chip8-render-pipeline-jobs-channel pipeline))
      (shutdown-executor
       (chip8-render-pipeline-executor pipeline)
       :wait
       t
       :cancel-pending
       t
       :timeout
       timeout)))
  pipeline)

(defun %ensure-open-render-pipeline (pipeline)
  (check-type pipeline chip8-render-pipeline)
  (when (chip8-render-pipeline-closed-p pipeline)
    (error "The CHIP-8 render pipeline is already closed."))
  pipeline)

(defun chip8-render-pipeline-submitted-rows (pipeline)
  "Return the number of rows submitted to worker tasks."
  (check-type pipeline chip8-render-pipeline)
  (atomic-counter-value (chip8-render-pipeline-submitted-counter pipeline)))

(defun chip8-render-pipeline-completed-rows (pipeline)
  "Return the number of row tasks completed by workers or the serial path."
  (check-type pipeline chip8-render-pipeline)
  (atomic-counter-value (chip8-render-pipeline-completed-counter pipeline)))

(defun chip8-render-pipeline-serial-rows (pipeline)
  "Return the number of rows rendered through the serial fallback."
  (check-type pipeline chip8-render-pipeline)
  (with-lock-held
      ((chip8-render-pipeline-lock pipeline))
    (chip8-render-pipeline-serial-row-count pipeline)))

(defun chip8-render-pipeline-queue-depth (pipeline)
  "Return PIPELINE's current executor queue depth."
  (check-type pipeline chip8-render-pipeline)
  (executor-queue-depth (chip8-render-pipeline-executor pipeline)))

(defun chip8-render-pipeline-high-water-mark (pipeline)
  "Return PIPELINE executor's maximum observed queue depth."
  (check-type pipeline chip8-render-pipeline)
  (executor-high-water-mark (chip8-render-pipeline-executor pipeline)))
