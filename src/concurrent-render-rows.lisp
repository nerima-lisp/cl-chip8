(in-package #:cl-chip8)

(defun %snapshot-framebuffer-row
    (framebuffer terminal-row &optional reusable-snapshot)
  (declare (type (array bit (* *)) framebuffer)
           (type fixnum terminal-row)
           (type (or null render-row-snapshot) reusable-snapshot))
  (let* ((y0 (ash terminal-row 1))
         (width (array-dimension framebuffer 1))
         (snapshot (or reusable-snapshot
                       (%make-render-row-snapshot
                        terminal-row
                        (make-array width :element-type (quote bit))
                        (make-array width :element-type (quote bit))))))
    (setf (render-row-snapshot-terminal-row snapshot) terminal-row)
    (dotimes (x width)
      (setf (sbit (render-row-snapshot-top-pixels snapshot) x)
            (aref framebuffer y0 x)
            (sbit (render-row-snapshot-bottom-pixels snapshot) x)
            (aref framebuffer (1+ y0) x)))
    snapshot))

(defun %snapshot-framebuffer-for-render
    (framebuffer previous-framebuffer)
  (declare (type (array bit (* *)) framebuffer)
           (type (or null (array bit (* *))) previous-framebuffer))
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (row-count (ash height -1))
         (same-geometry-p
           (and previous-framebuffer
                (= height (array-dimension previous-framebuffer 0))
                (= width (array-dimension previous-framebuffer 1))))
         (changed (make-array row-count
                              :element-type (quote bit)
                              :initial-element 0))
         (copy (make-array (array-dimensions framebuffer)
                           :element-type (quote bit))))
    (dotimes (y height)
      (let ((terminal-row (ash y -1)))
        (dotimes (x width)
          (let ((pixel (aref framebuffer y x)))
            (setf (aref copy y x) pixel)
            (unless (and same-geometry-p
                         (= pixel (aref previous-framebuffer y x)))
              (setf (sbit changed terminal-row) 1))))))
    (values changed copy)))

(defun %render-row-snapshot (snapshot &optional reusable-characters)
  (declare (type render-row-snapshot snapshot)
           (type (or null string) reusable-characters))
  (let* ((width (length (render-row-snapshot-top-pixels snapshot)))
         (characters (or reusable-characters (make-string width))))
    (dotimes (x width characters)
      (setf (char characters x)
            (half-block-character
             (sbit (render-row-snapshot-top-pixels snapshot) x)
             (sbit (render-row-snapshot-bottom-pixels snapshot) x))))))

(defun %ensure-render-buffers (pipeline row-count width)
  (declare (type chip8-render-pipeline pipeline)
           (type (integer 1 *) row-count width))
  (let ((snapshots (chip8-render-pipeline-snapshot-buffer pipeline))
        (results (chip8-render-pipeline-result-buffer pipeline)))
    (unless (and snapshots
                 (= (array-dimension snapshots 0) row-count)
                 (= (length
                     (render-row-snapshot-top-pixels (aref snapshots 0)))
                    width)
                 results
                 (= (array-dimension results 0) row-count)
                 (= (length (aref results 0)) width))
      (setf (chip8-render-pipeline-snapshot-buffer pipeline)
            (%make-render-snapshot-buffer row-count width)
            (chip8-render-pipeline-result-buffer pipeline)
            (%make-render-result-buffer row-count width)))
    (values (chip8-render-pipeline-snapshot-buffer pipeline)
            (chip8-render-pipeline-result-buffer pipeline))))

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
          do (progn
               ;; A timed-out worker may still signal this semaphore and write
               ;; the reusable result buffer. Retiring the whole pipeline is
               ;; the only safe way to prevent those stale completions from
               ;; being consumed by a later render.
               (%close-render-pipeline
                pipeline
                (chip8-render-pipeline-shutdown-timeout pipeline))
               (error "Render worker completion timed out.")))
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
  (declare (type (array bit (* *)) framebuffer)
           (type boolean sound-active-p))
  (check-type framebuffer (array bit (* *)))
  (check-type pipeline chip8-render-pipeline)
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1)))
    (unless (and (plusp height) (plusp width) (evenp height))
      (error "Framebuffer width must be positive and height must be positive and even."))
    (let* ((row-count (ash height -1))
           (default-threshold
             (ceiling (* row-count
                         +concurrent-render-default-parallel-threshold+)
                      +concurrent-render-reference-row-count+))
           (minimum-snapshot-count
             (ceiling (* row-count +concurrent-render-minimum-snapshots+)
                      +concurrent-render-reference-row-count+))
           (parallel-threshold
             (if (chip8-render-pipeline-parallel-threshold-supplied-p pipeline)
                 (chip8-render-pipeline-parallel-threshold pipeline)
                 default-threshold)))
      (with-lock-held ((chip8-render-pipeline-lock pipeline))
        (%ensure-open-render-pipeline pipeline)
        (%ensure-render-buffers pipeline row-count width)
        (let* ((state (chip8-render-pipeline-state pipeline))
               (snapshots (chip8-render-pipeline-snapshot-buffer pipeline))
               (previous-framebuffer
                 (chip8-render-pipeline-previous-framebuffer pipeline)))
          (multiple-value-bind (changed framebuffer-copy)
              (%snapshot-framebuffer-for-render
               framebuffer previous-framebuffer)
            (setf (fill-pointer snapshots) 0)
            (let ((count 0))
              (dotimes (terminal-row row-count)
                (when (= 1 (sbit changed terminal-row))
                  (%snapshot-framebuffer-row
                   framebuffer terminal-row (aref snapshots count))
                  (incf count)))
              (setf (fill-pointer snapshots) count)
              (with-screen-batch (screen)
                (if (and (< count row-count)
                         (>= count parallel-threshold)
                         (>= count minimum-snapshot-count))
                    (let ((results
                            (%render-snapshots-concurrently snapshots pipeline)))
                      (loop for snapshot across snapshots
                            for characters across results
                            do (%commit-render-row!
                                screen
                                (render-row-snapshot-terminal-row snapshot)
                                characters)))
                    (progn
                      (incf (chip8-render-pipeline-serial-row-count pipeline)
                            count)
                      (unless (= count row-count)
                        (atomic-counter-incf
                         (chip8-render-pipeline-completed-counter pipeline)
                         count))
                      (loop for snapshot across snapshots
                            do (%commit-render-row!
                                screen
                                (render-row-snapshot-terminal-row snapshot)
                                (%render-row-snapshot snapshot)))))
                (when (or (zerop (chip8-render-state-frame-count state))
                          (not (eql
                                sound-active-p
                                (chip8-render-state-sound-active-p state))))
                  (render-sound-indicator-into-screen! screen sound-active-p)))
              (setf (chip8-render-pipeline-previous-framebuffer pipeline)
                    framebuffer-copy
                    (chip8-render-state-sound-active-p state) sound-active-p)
              (incf (chip8-render-state-frame-count state)))))
        screen))))
