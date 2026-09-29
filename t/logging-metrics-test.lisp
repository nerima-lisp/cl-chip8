;;;; Tests for the logging and metrics boundaries.
;;;;
;;;; The logging assertions parse the emitted JSON with cl-json-kit rather than
;;;; searching the raw text, so a value that is merely present but wrong -- a
;;;; quoted number, a stale gauge, a doubled counter -- fails the test.

(in-package #:cl-chip8/test)

(defun %metrics-test-path (name)
  (merge-pathnames (format nil "cl-chip8-metrics-~A-~D.json" name (random 1000000))
                   (uiop:temporary-directory)))

(defun %read-log-records (path)
  "Parse PATH as newline-delimited JSON objects."
  (mapcar #'json-kit:parse
          (remove-if (lambda (line) (zerop (length line)))
                     (uiop:split-string (uiop:read-file-string path)
                                        :separator '(#\Newline)))))

(defun %log-field (record name)
  (gethash name (gethash "fields" record)))

(defun %emit-to-log (path emit)
  "Run EMIT against a file-backed logger and return the parsed records."
  (let ((logger (cl-chip8::make-chip8-logger :path path)))
    (unwind-protect
         (progn
           (funcall emit logger)
           (cl-chip8::flush-chip8-logger logger))
      (cl-chip8::close-chip8-logger logger)))
  (%read-log-records path))

(defun %finalized-fields (metrics &key instructions effective-hz render-pipeline)
  (cl-chip8::chip8-metrics-fields
   (cl-chip8::finalize-chip8-metrics! metrics
                                      :instructions instructions
                                      :effective-hz effective-hz
                                      :render-pipeline render-pipeline)))

(defun %metrics-test-framebuffer (terminal-rows)
  "A framebuffer with one lit pixel in each of TERMINAL-ROWS."
  (let ((framebuffer (make-array '(32 64) :element-type 'bit :initial-element 0)))
    (dolist (terminal-row terminal-rows framebuffer)
      (setf (aref framebuffer (ash terminal-row 1) 0) 1))))

(describe "logging and metrics"
  (it "emits one JSON record per line with parsed message, level and fields"
    (let ((path (%metrics-test-path "record")))
      (unwind-protect
           (let* ((records (%emit-to-log
                            path
                            (lambda (logger)
                              (cl-chip8::chip8-log-info
                               logger "started" '(:rom "test" :ticks 7)))))
                  (record (first records)))
            (expect (length records) :to-be 1)
            (expect (gethash "time" record) :to-be-type-of 'integer)
            (expect (gethash "level" record) :to-equal "INFO")
            (expect (gethash "logger" record) :to-equal "cl-chip8")
            (expect (gethash "message" record) :to-equal "started")
            (expect (%log-field record "rom") :to-equal "test")
            (expect (%log-field record "ticks") :to-be 7))
        (when (probe-file path)
          (delete-file path)))))

  (it "uses a null handler that creates no file"
    (let* ((directory (merge-pathnames
                       (format nil "cl-chip8-log-null-~D/" (random 1000000))
                       (uiop:temporary-directory)))
           (logger (cl-chip8::make-chip8-logger)))
      (uiop:ensure-directory-pathname directory)
      (unwind-protect
           (progn
             (expect logger :to-be-truthy)
             (cl-chip8::chip8-log-info logger "discarded" '(:rom "test"))
             (cl-chip8::flush-chip8-logger logger)
             (cl-chip8::close-chip8-logger logger)
             (expect (directory (merge-pathnames "*.*" directory)) :to-be-null))
        (when (probe-file directory)
          (uiop:delete-directory-tree directory)))))

  (it "logs the termination metrics and leaves the standard streams empty"
    (let ((path (%metrics-test-path "streams"))
          (standard-output-capture (make-string-output-stream))
          (error-output-capture (make-string-output-stream))
          records)
      (unwind-protect
           (let ((*standard-output* standard-output-capture)
                 (*error-output* error-output-capture))
             (setf records
                   (%emit-to-log
                    path
                    (lambda (logger)
                      (cl-chip8::chip8-log-info
                       logger
                       "metrics"
                       (%finalized-fields (cl-chip8::make-chip8-metrics)
                                          :instructions 4242
                                          :effective-hz 1234.5))))))
           (expect (get-output-stream-string standard-output-capture) :to-equal "")
           (expect (get-output-stream-string error-output-capture) :to-equal "")
           (expect (length records) :to-be 1)
           (expect (%log-field (first records) "chip8_instructions_total") :to-be 4242)
           (expect (%log-field (first records) "chip8_effective_hz") :to-equal 1234.5d0)
        (when (probe-file path)
          (delete-file path)))))

  (it "logs the instruction count, effective Hz and the pipeline's own row counters"
    (let ((path (%metrics-test-path "termination")))
      (unwind-protect
           (let* ((screen (cl-tty-kit:make-screen +screen-width+ +screen-height+))
                  (fields nil))
             (with-chip8-render-pipeline (pipeline :parallelism 2 :parallel-threshold 1)
               ;; The first render has no previous framebuffer, so all sixteen
               ;; terminal rows count as changed and take the serial fallback.
               (render-chip8-concurrently! screen
                                           (%metrics-test-framebuffer '())
                                           pipeline)
               ;; Eleven changed rows clear both the parallel threshold and the
               ;; minimum snapshot count, so the next render goes to the workers.
               (render-chip8-concurrently! screen
                                           (%metrics-test-framebuffer
                                            '(0 1 2 3 4 5 6 7 8 9 10))
                                           pipeline)
               ;; Three changed rows fall back to the serial path again.
               (render-chip8-concurrently! screen
                                           (%metrics-test-framebuffer '(3 4 5 6 7 8 9 10))
                                           pipeline)
               (expect (cl-chip8::chip8-render-pipeline-submitted-rows pipeline) :to-be 11)
               (expect (cl-chip8::chip8-render-pipeline-serial-rows pipeline) :to-be 19)
               (setf fields (%finalized-fields (cl-chip8::make-chip8-metrics)
                                               :instructions 4242
                                               :effective-hz 1234.5
                                               :render-pipeline pipeline)))
             (let* ((records (%emit-to-log
                              path
                              (lambda (logger)
                                (cl-chip8::chip8-log-info logger "metrics" fields))))
                    (record (first records)))
               (expect (gethash "message" record) :to-equal "metrics")
               (expect (%log-field record "chip8_instructions_total") :to-be 4242)
               (expect (%log-field record "chip8_effective_hz") :to-equal 1234.5d0)
               (expect (%log-field record "chip8_render_rows_worker_total") :to-be 11)
               (expect (%log-field record "chip8_render_rows_serial_total") :to-be 19)))
        (when (probe-file path)
          (delete-file path)))))

  (it "sets the effective Hz gauge instead of incrementing it"
    (let ((metrics (cl-chip8::make-chip8-metrics)))
      (%finalized-fields metrics :effective-hz 100)
      (expect (getf (%finalized-fields metrics :effective-hz 1234.5)
                    :chip8_effective_hz)
              :to-equal 1234.5)))

  (it "publishes a gauge cleared to zero instead of skipping the pending value"
    (let ((metrics (cl-chip8::make-chip8-metrics)))
      (%finalized-fields metrics :effective-hz 1234.5)
      (expect (getf (%finalized-fields metrics :effective-hz 0)
                    :chip8_effective_hz)
              :to-equal 0)))

  (it "reports counters that were never incremented as zero"
    (let* ((metrics (cl-chip8::make-chip8-metrics))
           (fields (%finalized-fields metrics :effective-hz 500)))
      (expect (getf fields :chip8_instructions_total) :to-be 0)
      (expect (getf fields :chip8_render_rows_worker_total) :to-be 0)
      (expect (getf fields :chip8_render_rows_serial_total) :to-be 0)))

  (it "applies the instruction count once across repeated finalizes"
    (let ((metrics (cl-chip8::make-chip8-metrics)))
      (%finalized-fields metrics :instructions 4242 :effective-hz 1234.5)
      (let ((second-pass (%finalized-fields metrics
                                             :instructions 4242
                                             :effective-hz 1234.5))
            (third-pass (%finalized-fields metrics
                                            :instructions 4242
                                            :effective-hz 1234.5)))
        (expect (getf second-pass :chip8_instructions_total) :to-be 4242)
        (expect (getf third-pass :chip8_instructions_total) :to-be 4242)
        (expect (getf third-pass :chip8_effective_hz) :to-equal 1234.5))))

  (it "reads the instruction count from the machine when no count is given"
    (let ((machine (make-chip8-machine)))
      (setf (chip8-machine-instructions machine) 4242)
      (expect (getf (cl-chip8::chip8-metrics-fields
                     (cl-chip8::finalize-chip8-metrics!
                      (cl-chip8::make-chip8-metrics) :machine machine))
                    :chip8_instructions_total)
              :to-be 4242)))

  (it "rejects a counter or gauge used with the wrong operation"
    (let ((metrics (cl-chip8::make-chip8-metrics)))
      (signals error (cl-chip8::chip8-metric-add metrics "chip8_effective_hz" 1))
      (signals error (cl-chip8::chip8-metric-set metrics "chip8_instructions_total" 1))
      (signals error (cl-chip8::chip8-metric-add metrics "chip8_render_frames_total" 1))))

  (it "registers no metric that no source can feed"
    (let* ((snapshots (cl-chip8::chip8-metrics-snapshot (cl-chip8::make-chip8-metrics)))
           (names (mapcar #'cl-observability-kit:metric-snapshot-name snapshots)))
      (expect (member "chip8_render_frames_total" names :test #'string=) :to-be-null)
      (expect (cl-observability-kit:metric-snapshot-unit
               (find "chip8_effective_hz" snapshots
                     :key #'cl-observability-kit:metric-snapshot-name
                     :test #'string=))
              :to-equal "Hz"))))
