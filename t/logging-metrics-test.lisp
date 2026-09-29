;;;; Tests for the logging and metrics boundaries.

(in-package #:cl-chip8/test)

(describe "logging and metrics"
  (it "writes JSON to a file and never to standard output"
    (let* ((path (merge-pathnames
                  (format nil "cl-chip8-log-~D.json" (random 1000000))
                  (uiop:temporary-directory)))
           (logger (cl-chip8::make-chip8-logger :path path)))
      (unwind-protect
           (progn
             (cl-chip8::chip8-log-info logger "started" '(:rom "test"))
             (cl-chip8::flush-chip8-logger logger)
             (let ((contents (uiop:read-file-string path)))
               (expect (search "\"message\":\"started\"" contents))
               (expect (search "\"fields\"" contents))))
        (cl-chip8::close-chip8-logger logger)
        (when (probe-file path)
          (delete-file path)))))

  (it "uses a null handler without a file"
    (let ((logger (cl-chip8::make-chip8-logger)))
      (expect logger)
      (cl-chip8::close-chip8-logger logger)))

  (it "applies command counts only at termination"
    (let ((metrics (cl-chip8::make-chip8-metrics)))
      (dotimes (i 3)
        (cl-chip8::record-chip8-instruction! metrics))
      (let ((before (cl-chip8::chip8-metrics-snapshot metrics)))
        (expect (= 0
                   (cl-observability-kit:metric-sample-value
                    (first
                     (cl-observability-kit:metric-snapshot-samples
                      (find-if (lambda (snapshot)
                                 (string= "chip8_instructions_total"
                                          (cl-observability-kit:metric-snapshot-name snapshot)))
                               before)))))))
      (let ((after (cl-chip8::finalize-chip8-metrics! metrics)))
        (expect (= 3
                   (cl-observability-kit:metric-sample-value
                    (first
                     (cl-observability-kit:metric-snapshot-samples
                      (find-if (lambda (snapshot)
                                 (string= "chip8_instructions_total"
                                          (cl-observability-kit:metric-snapshot-name snapshot)))
                               after))))))))))
