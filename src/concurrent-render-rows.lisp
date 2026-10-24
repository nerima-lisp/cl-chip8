(in-package #:cl-chip8)

(defun %snapshot-framebuffer-row
    (framebuffer terminal-row source-rows-per-cell &optional reusable-snapshot)
  (declare (type (array * (* *)) framebuffer)
           (type fixnum terminal-row)
           (type (integer 1 *) source-rows-per-cell)
           (type (or null render-row-snapshot) reusable-snapshot))
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (snapshot (or reusable-snapshot
                       (%make-render-row-snapshot
                        terminal-row
                        (make-array (list source-rows-per-cell width)
                                    :initial-element 0))))
         (pixels (render-row-snapshot-pixels snapshot)))
    (setf (render-row-snapshot-terminal-row snapshot) terminal-row)
    (dotimes (source-row source-rows-per-cell)
      (let ((source-y (+ (* terminal-row source-rows-per-cell) source-row)))
        (dotimes (x width)
          (setf (aref pixels source-row x)
                (if (< source-y height)
                    (aref framebuffer source-y x)
                    0)))))
    snapshot))

(defun %snapshot-framebuffer-for-render
    (framebuffer previous-framebuffer previous-mode mode row-count
     source-rows-per-cell previous-palette-generation palette-generation)
  (declare (type (array * (* *)) framebuffer)
           (type (or null (array * (* *))) previous-framebuffer)
           (type (or null (member :lores :half-block :quarter-block :braille))
                 previous-mode)
           (type (member :lores :half-block :quarter-block :braille) mode)
           (type (integer 1 *) row-count source-rows-per-cell)
           (type (or null (integer 0 *)) previous-palette-generation)
           (type (integer 0 *) palette-generation))
  (let* ((height (array-dimension framebuffer 0))
         (width (array-dimension framebuffer 1))
         (same-geometry-p
           (and previous-framebuffer
                (eq previous-mode mode)
                (= height (array-dimension previous-framebuffer 0))
                (= width (array-dimension previous-framebuffer 1))))
         (palette-changed-p
           (not (eql previous-palette-generation palette-generation)))
         (changed (make-array row-count
                              :element-type 'bit
                              :initial-element 0))
         (copy (make-array (array-dimensions framebuffer)
                           :initial-element 0)))
    (dotimes (y height)
      (let ((terminal-row (floor y source-rows-per-cell)))
        (dotimes (x width)
          (let ((pixel (aref framebuffer y x)))
            (unless (typep pixel '(integer 0 3))
              (error "Framebuffer pixels must be integers from 0 through 3."))
            (setf (aref copy y x) pixel)
            (unless (and same-geometry-p
                         (not palette-changed-p)
                         (eql pixel (aref previous-framebuffer y x)))
              (setf (sbit changed terminal-row) 1))))))
    (unless (and same-geometry-p (not palette-changed-p))
      (fill changed 1))
    (values changed copy)))

(defun %render-row-snapshot
    (snapshot mode &optional reusable-characters reusable-styles
       (palette *chip8-render-palette*))
  (declare (type render-row-snapshot snapshot)
           (type (member :lores :half-block :quarter-block :braille) mode)
           (type (or null string) reusable-characters)
           (type (simple-array t (4)) palette))
  (%render-framebuffer-row-data
   (render-row-snapshot-pixels snapshot)
   0
   mode
   reusable-characters
   reusable-styles
   palette))

(defun %ensure-render-buffers
    (pipeline row-count source-width output-width source-rows-per-cell)
  (declare (type chip8-render-pipeline pipeline)
           (type (integer 1 *) row-count source-width output-width
                 source-rows-per-cell))
  (let ((snapshots (chip8-render-pipeline-snapshot-buffer pipeline))
        (results (chip8-render-pipeline-result-buffer pipeline))
        (styles (chip8-render-pipeline-style-buffer pipeline)))
    (unless (and snapshots
                 (= (array-dimension snapshots 0) row-count)
                 (= (array-dimension
                     (render-row-snapshot-pixels (aref snapshots 0)) 0)
                    source-rows-per-cell)
                 (= (array-dimension
                     (render-row-snapshot-pixels (aref snapshots 0)) 1)
                    source-width)
                 results
                 (= (array-dimension results 0) row-count)
                 (= (length (aref results 0)) output-width)
                 styles
                 (= (array-dimension styles 0) row-count))
      (setf (chip8-render-pipeline-snapshot-buffer pipeline)
            (%make-render-snapshot-buffer
             row-count source-width source-rows-per-cell)
            (chip8-render-pipeline-result-buffer pipeline)
            (%make-render-result-buffer row-count output-width)
            (chip8-render-pipeline-style-buffer pipeline)
            (%make-render-style-buffer row-count)))
    (values (chip8-render-pipeline-snapshot-buffer pipeline)
            (chip8-render-pipeline-result-buffer pipeline)
            (chip8-render-pipeline-style-buffer pipeline))))

(defun %submit-render-batch-jobs
    (snapshots results row-styles mode palette job-buffer jobs-channel worker-count
     chunk-size)
  (loop for job-index below worker-count
        for start = (* job-index chunk-size)
        for end = (min (length snapshots) (+ start chunk-size))
        do (let ((job (aref job-buffer job-index)))
             (setf (render-batch-job-snapshots job) snapshots
                   (render-batch-job-results job) results
                   (render-batch-job-row-styles job) row-styles
                   (render-batch-job-mode job) mode
                   (render-batch-job-palette job) palette
                   (render-batch-job-start job) start
                   (render-batch-job-end job) end
                   (render-batch-job-caught-condition job) nil)
             (unless (try-send jobs-channel job)
               (error "Render job channel is unexpectedly full or closed.")))))

(defun %render-snapshots-concurrently (snapshots pipeline mode palette)
  (let* ((count (length snapshots))
         (parallelism (chip8-render-pipeline-parallelism pipeline))
         (workers (min parallelism (max 1 (ceiling count +concurrent-render-rows-per-job+))))
         (chunk-size (max 1 (ceiling count workers)))
         (results (chip8-render-pipeline-result-buffer pipeline))
         (row-styles (chip8-render-pipeline-style-buffer pipeline))
         (jobs (chip8-render-pipeline-job-buffer pipeline)))
    (setf (fill-pointer results) count
          (fill-pointer row-styles) count)
    (atomic-counter-incf (chip8-render-pipeline-submitted-counter pipeline) count)
    (%submit-render-batch-jobs
     snapshots results row-styles mode palette jobs
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
    (values results row-styles)))

(defun %commit-render-row! (screen terminal-row characters &optional styles)
  (if styles
      (loop for character across characters
            for x from 0
            for style across styles
            do (cl-tty-kit:screen-put-cell
                screen
                (+ +playfield-origin-x+ x)
                (+ +playfield-origin-y+ terminal-row)
                character
                :style style))
      (screen-write-string screen +playfield-origin-x+
                           (+ +playfield-origin-y+ terminal-row)
                           characters)))

(defun render-chip8-concurrently!
    (screen framebuffer pipeline &key (sound-active-p nil) (mode :lores))
  (declare (type (array * (* *)) framebuffer)
           (type boolean sound-active-p))
  (check-type framebuffer (array * (* *)))
  (check-type mode (member :lores :half-block :quarter-block :braille))
  (check-type pipeline chip8-render-pipeline)
  (let* ((palette-snapshot (%capture-chip8-render-palette-snapshot))
         (palette-generation
           (chip8-render-palette-snapshot-generation palette-snapshot))
         (palette (chip8-render-palette-snapshot-colors palette-snapshot))
         (height (array-dimension framebuffer 0))
         (source-rows-per-terminal-row (%pixels-per-terminal-row mode))
         (width (array-dimension framebuffer 1)))
    (unless (and (plusp height) (plusp width))
      (error "Framebuffer dimensions must be positive."))
    (multiple-value-bind (output-width row-count source-rows-per-cell)
        (case mode
          ((:lores :half-block)
           (values width (ceiling height source-rows-per-terminal-row)
                   source-rows-per-terminal-row))
          (:quarter-block
           (unless (and (evenp height) (evenp width))
             (error "Quarter-block mode requires even framebuffer dimensions."))
           (values (ash width -1) (ceiling height source-rows-per-terminal-row)
                   source-rows-per-terminal-row))
          (:braille
           (unless (and (evenp width) (zerop (mod height 4)))
             (error "Braille mode requires even width and height divisible by four."))
           (values (ash width -1) (ceiling height source-rows-per-terminal-row)
                   source-rows-per-terminal-row)))
      (let* ((default-threshold
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
          (%ensure-render-buffers
           pipeline row-count width output-width source-rows-per-cell)
          (let* ((state (chip8-render-pipeline-state pipeline))
                 (snapshots (chip8-render-pipeline-snapshot-buffer pipeline))
                 (results (chip8-render-pipeline-result-buffer pipeline))
                 (row-styles (chip8-render-pipeline-style-buffer pipeline))
                 (previous-framebuffer (chip8-render-state-framebuffer state))
                 (previous-mode (chip8-render-state-display-mode state))
                 (previous-palette-generation
                   (chip8-render-state-palette-generation state)))
            (multiple-value-bind (changed framebuffer-copy)
                (%snapshot-framebuffer-for-render
                 framebuffer
                 previous-framebuffer
                 previous-mode
                 mode
                 row-count
                 source-rows-per-cell
                 previous-palette-generation
                 palette-generation)
              (setf (fill-pointer snapshots) 0)
              (let ((count 0))
                (dotimes (terminal-row row-count)
                  (when (= 1 (sbit changed terminal-row))
                    (%snapshot-framebuffer-row
                     framebuffer-copy terminal-row source-rows-per-cell
                     (aref snapshots count))
                    (incf count)))
                (setf (fill-pointer snapshots) count)
                (with-screen-batch (screen)
                  (if (and
                       (>= count parallel-threshold)
                       (>= count minimum-snapshot-count))
                      (multiple-value-bind (rendered-rows rendered-styles)
                          (%render-snapshots-concurrently
                           snapshots pipeline mode palette)
                        (loop for snapshot across snapshots
                              for characters across rendered-rows
                              for styles across rendered-styles
                              do (%commit-render-row!
                                  screen
                                  (render-row-snapshot-terminal-row snapshot)
                                  characters
                                  styles)))
                      (progn
                        (incf (chip8-render-pipeline-serial-row-count pipeline)
                              count)
                        (unless (= count row-count)
                          (atomic-counter-incf
                           (chip8-render-pipeline-completed-counter pipeline)
                           count))
                        (loop for snapshot across snapshots
                              for index from 0
                              do (multiple-value-bind (characters styles)
                                     (%render-row-snapshot
                                      snapshot
                                      mode
                                      (aref results index)
                                      (aref row-styles index)
                                      palette)
                                   (setf (aref results index) characters
                                         (aref row-styles index) styles)
                                   (%commit-render-row!
                                    screen
                                    (render-row-snapshot-terminal-row snapshot)
                                    characters
                                    styles)))))
                  (when (or (null (chip8-render-state-framebuffer state))
                            (zerop (chip8-render-state-frame-count state))
                            (not (eql
                                  sound-active-p
                                  (chip8-render-state-sound-active-p state))))
                    (render-sound-indicator-into-screen! screen sound-active-p))
                  (setf (chip8-render-state-framebuffer state)
                        framebuffer-copy
                        (chip8-render-state-display-mode state) mode
                        (chip8-render-state-palette-generation state)
                        palette-generation
                        (chip8-render-state-sound-active-p state) sound-active-p)
                  (incf (chip8-render-state-frame-count state)))))
          screen))))))
