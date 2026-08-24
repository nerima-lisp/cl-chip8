(in-package #:cl-chip8)

(declaim (inline %render-row-snapshot)
         (ftype (function (render-row-snapshot &optional (or null string))
                          string)
                %render-row-snapshot))

(defun %snapshot-display-row-under-lock
    (terminal-row &optional reusable-snapshot)
  (declare (type display-terminal-row terminal-row)
           (type (or null render-row-snapshot) reusable-snapshot))
  (let* ((y0 (ash terminal-row 1))
         (snapshot
           (or reusable-snapshot
               (%make-render-row-snapshot
                terminal-row
                (make-array
                 +display-width+
                 :element-type (quote bit))
                (make-array
                 +display-width+
                 :element-type (quote bit))
                0
                0)))
         (top-pixels (render-row-snapshot-top-pixels snapshot))
         (bottom-pixels (render-row-snapshot-bottom-pixels snapshot)))
    (declare (type display-row y0)
             (type render-row-snapshot snapshot)
             (type display-row-bits top-pixels bottom-pixels))
    (setf (render-row-snapshot-terminal-row snapshot) terminal-row
          (render-row-snapshot-top-generation snapshot)
          (aref *display-row-generations* y0)
          (render-row-snapshot-bottom-generation snapshot)
          (aref *display-row-generations* (1+ y0)))
    (dotimes (x +display-width+)
      (declare (type display-column x))
      (setf (sbit top-pixels x) (%display-pixel-value x y0)
            (sbit bottom-pixels x) (%display-pixel-value x (1+ y0))))
    snapshot))

(defun %snapshot-dirty-display-rows-under-lock
    (&optional snapshot-buffer)
  (declare (type (or null (vector t 16)) snapshot-buffer))
  (let ((snapshots
          (or snapshot-buffer
              (make-array *display-dirty-terminal-row-count*)))
        (index 0))
    (declare (type (vector t *) snapshots)
             (type (integer 0 16) index))
    (when snapshot-buffer
      (setf (fill-pointer snapshots) 0))
    (dotimes (terminal-row +display-terminal-row-count+)
      (declare (type display-terminal-row terminal-row))
      (let ((y0 (ash terminal-row 1)))
        (declare (type display-row y0))
        (when (or (plusp (sbit *display-dirty-rows* y0))
                  (plusp (sbit *display-dirty-rows* (1+ y0))))
          (setf (aref snapshots index)
                (%snapshot-display-row-under-lock
                 terminal-row
                 (and snapshot-buffer
                      (aref snapshots index))))
          (incf index))))
    (when snapshot-buffer
      (setf (fill-pointer snapshots) index))
    snapshots))

(defun %clear-rendered-display-rows! (snapshots)
  (with-display-lock
    (loop for snapshot across snapshots
          do (%clear-display-terminal-row-if-unchanged!
              (render-row-snapshot-terminal-row snapshot)
              (render-row-snapshot-top-generation snapshot)
              (render-row-snapshot-bottom-generation snapshot))))
  snapshots)

(defun %render-row-snapshot (snapshot &optional reusable-characters)
  "Convert a private row snapshot into terminal characters."
  (declare (type render-row-snapshot snapshot)
           (type (or null string) reusable-characters))
  (let ((characters (or reusable-characters
                        (make-string +display-width+))))
    (declare (type string characters))
    (dotimes (x +display-width+)
      (declare (type display-column x))
      (setf (char characters x)
            (half-block-character
             (sbit (render-row-snapshot-top-pixels snapshot) x)
             (sbit (render-row-snapshot-bottom-pixels snapshot) x))))
    characters))

(defun %render-batch-deadline (shutdown-timeout)
  "Return the absolute internal-time deadline for a render batch."
  (declare (type duration shutdown-timeout))
  (+ (get-internal-real-time)
     (round (* (duration-to-seconds shutdown-timeout)
               internal-time-units-per-second))))

(defun %submit-render-batch-jobs
    (snapshots results job-buffer jobs-channel worker-count chunk-size)
  "Fill reusable jobs and submit the batches to JOBS-CHANNEL."
  (declare (type (vector t *) snapshots results job-buffer)
           (type render-channel jobs-channel)
           (type (integer 1 16) worker-count chunk-size))
  (loop for job-index below worker-count
        for start = (* job-index chunk-size)
        for end = (min (length snapshots) (+ start chunk-size))
        do (let ((job (aref job-buffer job-index)))
             (setf (render-batch-job-snapshots job) snapshots
                   (render-batch-job-results job) results
                   (render-batch-job-start job) start
                   (render-batch-job-end job) end
                   (render-batch-job-caught-condition job) nil)
             (unless (try-send jobs-channel job)
               (error "Render job channel is unexpectedly full or closed.")))))

(defun %wait-for-render-batch-jobs
    (completion-semaphore worker-count deadline shutdown-timeout)
  "Wait for all workers, failing when the shared deadline is exhausted."
  (declare (type render-semaphore completion-semaphore)
           (type (integer 1 16) worker-count)
           (type integer deadline)
           (type duration shutdown-timeout))
  (loop repeat worker-count
        unless
            (wait-on-semaphore
             completion-semaphore
             :timeout
             (max
              0.0d0
              (/ (- deadline (get-internal-real-time))
                 (float internal-time-units-per-second 0.0d0))))
        do (error "Render worker completion timed out after ~A."
                  shutdown-timeout)))

(defun %first-render-batch-condition (job-buffer worker-count)
  "Return the first condition captured by a completed render batch."
  (declare (type (vector t *) job-buffer)
           (type (integer 1 16) worker-count))
  (loop with first-condition = nil
        for job-index below worker-count
        for condition =
          (render-batch-job-caught-condition (aref job-buffer job-index))
        when (and condition (null first-condition))
          do (setf first-condition condition)
        finally (return first-condition)))

(declaim (inline %advance-render-serial-row-count!))

(defun %advance-render-serial-row-count! (pipeline row-count)
  (declare (type chip8-render-pipeline pipeline)
           (type (integer 0 16) row-count))
  (setf (chip8-render-pipeline-serial-row-count pipeline)
        (ldb (byte 64 0)
             (+ (chip8-render-pipeline-serial-row-count pipeline)
                row-count))))

(defun %commit-render-row! (screen terminal-row characters)
  (declare (type display-terminal-row terminal-row)
           (type string characters))
  (screen-write-string
   screen
   +playfield-origin-x+
   (+ +playfield-origin-y+ terminal-row)
   characters))

(defun %render-snapshots-concurrently
    (snapshots pipeline)
  (declare (type (vector t *) snapshots)
           (type chip8-render-pipeline pipeline))
  (let* ((snapshot-count (length snapshots))
         (parallelism (chip8-render-pipeline-parallelism pipeline))
         (worker-count
           (min parallelism
                (max 1
                     (ceiling snapshot-count
                              +concurrent-render-rows-per-job+))))
         (chunk-size (max 1 (ceiling snapshot-count worker-count)))
         (results
           (the (vector t 16)
                (chip8-render-pipeline-result-buffer pipeline)))
         (job-buffer
           (the (vector t *)
                (chip8-render-pipeline-job-buffer pipeline)))
         (jobs-channel
           (the render-channel
                (chip8-render-pipeline-jobs-channel pipeline)))
         (completion-semaphore
           (the render-semaphore
                (chip8-render-pipeline-completion-semaphore pipeline)))
         (shutdown-timeout
           (the duration
                (chip8-render-pipeline-shutdown-timeout pipeline)))
         (deadline
           (%render-batch-deadline shutdown-timeout)))
    (declare (type (integer 0 16) snapshot-count)
             (type (integer 1 *) parallelism)
             (type (integer 1 16) worker-count chunk-size)
             (type (vector t 16) results)
             (type (vector t *) job-buffer)
             (type render-channel jobs-channel)
             (type render-semaphore completion-semaphore)
             (type duration shutdown-timeout))
    (setf (fill-pointer results) snapshot-count)
    (atomic-counter-incf
     (chip8-render-pipeline-submitted-counter pipeline)
     snapshot-count)
    (%submit-render-batch-jobs
     snapshots results job-buffer jobs-channel worker-count chunk-size)
    (%wait-for-render-batch-jobs
     completion-semaphore worker-count deadline shutdown-timeout)
    (let ((first-condition
            (%first-render-batch-condition job-buffer worker-count)))
      (when first-condition
        (error first-condition)))
    results))

(defun %render-full-frame-serially-under-lock (screen pipeline)
  "Render a full dirty frame while the display lock is already held."
  (%advance-render-serial-row-count!
   pipeline
   +display-terminal-row-count+)
  (with-screen-batch
      (screen)
    (%render-display-into-screen!
     screen
     (the (vector t 16)
          (chip8-render-pipeline-result-buffer pipeline)))
    (render-sound-indicator-into-screen! screen))
  (fill *display-dirty-rows* 0)
  (setf *display-dirty-terminal-row-count* 0)
  screen)

(defun %cck-render-eligible-p
    (snapshot-count pipeline)
  "Return true when the configured threshold and measured CCK floor are met."
  (declare (type (integer 0 16) snapshot-count)
           (type chip8-render-pipeline pipeline))
  (and
   (>= snapshot-count
       (chip8-render-pipeline-parallel-threshold pipeline))
   (>= snapshot-count
       +concurrent-render-minimum-snapshots+)))

(defun %render-dirty-display-rows-serially-under-lock (screen pipeline)
  "Render dirty rows directly while the display lock is held."
  (let ((completed 0))
    (declare (type (integer 0 16) completed))
    (%advance-render-serial-row-count!
     pipeline
     *display-dirty-terminal-row-count*)
    (unwind-protect
        (progn
          (with-screen-batch
              (screen)
            (dotimes (terminal-row +display-terminal-row-count+)
              (declare (type display-terminal-row terminal-row))
              (let ((y0 (ash terminal-row 1)))
                (declare (type display-row y0))
                (when (or (plusp (sbit *display-dirty-rows* y0))
                          (plusp (sbit *display-dirty-rows* (1+ y0))))
                  (%render-display-row-into-screen!
                   screen
                   terminal-row
                   (the (vector t 16)
                        (chip8-render-pipeline-result-buffer pipeline)))
                  (incf completed))))
            (render-sound-indicator-into-screen! screen))
          (fill *display-dirty-rows* 0)
          (setf *display-dirty-terminal-row-count* 0)
          screen)
      (atomic-counter-incf
       (chip8-render-pipeline-completed-counter pipeline)
       completed))))

(defun render-chip8-concurrently! (screen pipeline)
  "Render dirty rows through PIPELINE and commit cells into SCREEN.
All reads from *DISPLAY* and all SCREEN mutations happen on the caller thread.
Worker tasks only process immutable bit-vector snapshots.
A full dirty frame uses the direct renderer without allocating row snapshots.
Partial batches use the persistent executor only when they meet both the
configured threshold and the measured minimum batch size. Smaller batches use
the serial fallback. The sound indicator remains part of the serial terminal
boundary. Render and close transitions are serialized by the pipeline lock.
Returns SCREEN."
  (check-type pipeline chip8-render-pipeline)
  (with-lock-held
      ((chip8-render-pipeline-lock pipeline))
    (%ensure-open-render-pipeline pipeline)
    (let (snapshots)
      (with-display-lock
        (when (%display-all-terminal-rows-dirty-p)
          (return-from render-chip8-concurrently!
            (%render-full-frame-serially-under-lock screen pipeline)))
        (if (%cck-render-eligible-p
             *display-dirty-terminal-row-count*
             pipeline)
            (setf snapshots
                  (%snapshot-dirty-display-rows-under-lock
                   (chip8-render-pipeline-snapshot-buffer pipeline)))
            (return-from render-chip8-concurrently!
              (%render-dirty-display-rows-serially-under-lock
               screen
               pipeline))))
      (let ((results (%render-snapshots-concurrently snapshots pipeline)))
        (with-screen-batch
            (screen)
          (loop for snapshot across snapshots
                for characters across results
                do (%commit-render-row!
                    screen
                    (render-row-snapshot-terminal-row snapshot)
                    characters))
          (render-sound-indicator-into-screen! screen))
        (%clear-rendered-display-rows! snapshots)))
    screen))
