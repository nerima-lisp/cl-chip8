(in-package #:cl-chip8)

(defun %snapshot-framebuffer-row
    (framebuffer terminal-row &optional reusable-snapshot)
  (declare (type display-framebuffer framebuffer)
           (type display-terminal-row terminal-row)
           (type (or null render-row-snapshot) reusable-snapshot))
  (let* ((y0 (ash terminal-row 1))
         (snapshot (or reusable-snapshot
                       (%make-render-row-snapshot
                        terminal-row
                        (make-array +display-width+ :element-type 'bit)
                        (make-array +display-width+ :element-type 'bit)))))
    (dotimes (x +display-width+)
      (setf (sbit (render-row-snapshot-top-pixels snapshot) x)
            (aref framebuffer y0 x)
            (sbit (render-row-snapshot-bottom-pixels snapshot) x)
            (aref framebuffer (1+ y0) x)))
    snapshot))

(defun %render-row-snapshot (snapshot &optional reusable-characters)
  (declare (type render-row-snapshot snapshot)
           (type (or null string) reusable-characters))
  (let ((characters (or reusable-characters (make-string +display-width+))))
    (dotimes (x +display-width+ characters)
      (setf (char characters x)
            (half-block-character
             (sbit (render-row-snapshot-top-pixels snapshot) x)
             (sbit (render-row-snapshot-bottom-pixels snapshot) x))))))

(defun %submit-render-batch-jobs
    (snapshots results job-buffer jobs-channel worker-count chunk-size)
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

(defun %render-snapshots-concurrently (snapshots pipeline)
  (let* ((count (length snapshots))
         (parallelism (chip8-render-pipeline-parallelism pipeline))
         (workers (min parallelism (max 1 (ceiling count +concurrent-render-rows-per-job+))))
         (chunk-size (max 1 (ceiling count workers)))
         (results (chip8-render-pipeline-result-buffer pipeline))
         (jobs (chip8-render-pipeline-job-buffer pipeline)))
    (setf (fill-pointer results) count)
    (atomic-counter-incf (chip8-render-pipeline-submitted-counter pipeline) count)
    (%submit-render-batch-jobs snapshots results jobs
                               (chip8-render-pipeline-jobs-channel pipeline)
                               workers chunk-size)
    (loop repeat workers
          unless (wait-on-semaphore
                  (chip8-render-pipeline-completion-semaphore pipeline)
                  :timeout
                  (duration-to-seconds
                   (chip8-render-pipeline-shutdown-timeout pipeline)))
          do (error "Render worker completion timed out."))
    (loop for i below workers
          for condition = (render-batch-job-caught-condition (aref jobs i))
          when condition do (error condition))
    results))

(defun %commit-render-row! (screen terminal-row characters)
  (screen-write-string screen +playfield-origin-x+
                       (+ +playfield-origin-y+ terminal-row)
                       characters))

(defun render-chip8-concurrently!
    (screen framebuffer pipeline &key (sound-active-p nil))
  (declare (type display-framebuffer framebuffer)
           (type boolean sound-active-p))
  (check-type pipeline chip8-render-pipeline)
  (with-lock-held ((chip8-render-pipeline-lock pipeline))
    (%ensure-open-render-pipeline pipeline)
    (let* ((state (chip8-render-pipeline-state pipeline))
           (changed (%changed-terminal-rows state framebuffer))
           (snapshots (make-array +display-terminal-row-count+
                                  :element-type 't :fill-pointer 0))
           (count 0))
      (dotimes (terminal-row +display-terminal-row-count+)
        (when (plusp (sbit changed terminal-row))
          (vector-push (%snapshot-framebuffer-row framebuffer terminal-row)
                       snapshots)
          (incf count)))
      (with-screen-batch (screen)
        (if (and (< count +display-terminal-row-count+)
                 (>= count (chip8-render-pipeline-parallel-threshold pipeline))
                 (>= count +concurrent-render-minimum-snapshots+))
            (let ((results (%render-snapshots-concurrently snapshots pipeline)))
              (loop for snapshot across snapshots
                    for characters across results
                    do (%commit-render-row!
                        screen (render-row-snapshot-terminal-row snapshot)
                        characters)))
            (progn
              (incf (chip8-render-pipeline-serial-row-count pipeline) count)
              (unless (= count +display-terminal-row-count+)
                (atomic-counter-incf
                 (chip8-render-pipeline-completed-counter pipeline)
                 count))
              (loop for snapshot across snapshots
                    do (%commit-render-row!
                        screen (render-row-snapshot-terminal-row snapshot)
                        (%render-row-snapshot snapshot)))))
        (when (or (null (chip8-render-state-framebuffer state))
                  (not (eql sound-active-p (chip8-render-state-sound-active-p state))))
          (render-sound-indicator-into-screen! screen sound-active-p)))
      (setf (chip8-render-state-framebuffer state) (%copy-framebuffer framebuffer)
            (chip8-render-state-sound-active-p state) sound-active-p)
      screen)))
