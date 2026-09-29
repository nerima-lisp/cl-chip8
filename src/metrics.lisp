;;;; Metrics boundary for the CHIP-8 application.

(in-package #:cl-chip8)

(defstruct (chip8-metrics (:constructor %make-chip8-metrics))
  registry
  counters
  pending)

(defvar *chip8-metrics* nil)

(defun %chip8-observability-function (name)
  (%chip8-package-function "CL-OBSERVABILITY-KIT" name))

(defun %chip8-observability-macro-symbol (name)
  (let* ((package (find-package "CL-OBSERVABILITY-KIT"))
         (symbol (and package (find-symbol name package))))
    (unless (and symbol (macro-function symbol))
      (error "Required CL-OBSERVABILITY-KIT::~A macro is unavailable." name))
    symbol))

(defun %define-chip8-metric (registry name help kind)
  ;; DEFINE-COUNTER is intentionally evaluated only during setup.  Runtime
  ;; command paths update the local pending table, never the external metric.
  (eval (list (%chip8-observability-macro-symbol
               (if (eq kind :gauge) "DEFINE-GAUGE" "DEFINE-COUNTER"))
              registry (intern name (find-package "CL-CHIP8"))
              :help help)))

(defun make-chip8-metrics ()
  (let* ((make-registry (%chip8-observability-function "MAKE-METRIC-REGISTRY"))
         (registry (funcall make-registry :scope-name "cl-chip8"))
         (counters (make-hash-table :test #'equal))
         (pending (make-hash-table :test #'equal)))
    (dolist (spec '(("chip8_instructions_total" "Executed CHIP-8 instructions." :counter)
                    ("chip8_effective_hz" "Effective instruction rate." :gauge)
                    ("chip8_render_rows_worker_total" "Rendered rows in workers." :counter)
                    ("chip8_render_rows_serial_total" "Rendered rows serially." :counter)
                    ("chip8_render_frames_total" "Rendered frames." :counter)))
      (setf (gethash (car spec) counters)
            (%define-chip8-metric registry (first spec) (second spec) (third spec))
            (gethash (car spec) pending) 0))
    (%make-chip8-metrics :registry registry :counters counters :pending pending)))

(defun chip8-metric-add (metrics name &optional (amount 1))
  "Record AMOUNT locally.  No cl-observability-kit operation occurs here."
  (check-type metrics chip8-metrics)
  (unless (gethash name (chip8-metrics-counters metrics))
    (error "Unknown CHIP-8 metric ~S." name))
  (incf (gethash name (chip8-metrics-pending metrics)) amount))

(defun chip8-metric-set (metrics name value)
  "Set a gauge at the termination boundary, not in the instruction hot path."
  (check-type metrics chip8-metrics)
  (unless (gethash name (chip8-metrics-counters metrics))
    (error "Unknown CHIP-8 metric ~S." name))
  (setf (gethash name (chip8-metrics-pending metrics)) value))

(defun record-chip8-instruction! (metrics)
  (chip8-metric-add metrics "chip8_instructions_total"))

(defun flush-chip8-metrics! (metrics)
  "Apply pending values once, normally from the run termination boundary."
  (check-type metrics chip8-metrics)
  (let ((metric-inc (%chip8-observability-function "METRIC-INC")))
    (maphash (lambda (name metric)
               (let ((amount (gethash name (chip8-metrics-pending metrics) 0)))
                 (when (plusp amount)
                   (funcall metric-inc metric amount)
                   (setf (gethash name (chip8-metrics-pending metrics)) 0))))
             (chip8-metrics-counters metrics)))
  metrics)

(defun finalize-chip8-metrics! (metrics &key machine instructions effective-hz)
  (when machine
    (setf instructions (chip8-machine-instructions machine)))
  (when instructions
    (chip8-metric-add metrics "chip8_instructions_total" instructions))
  (when effective-hz
    (chip8-metric-set metrics "chip8_effective_hz" effective-hz))
  (flush-chip8-metrics! metrics)
  (chip8-metrics-snapshot metrics))

(defun chip8-metrics-fields (snapshot)
  "Flatten a label-free snapshot into fields suitable for log-kit."
  (loop for item in snapshot
        for sample = (first (observability-kit:metric-snapshot-samples item))
        append (list (intern (string-upcase
                              (observability-kit:metric-snapshot-name item)) :keyword)
                     (observability-kit:metric-sample-value sample))))

(defun chip8-metrics-snapshot (metrics)
  (check-type metrics chip8-metrics)
  (funcall (%chip8-observability-function "METRIC-SNAPSHOT")
           (chip8-metrics-registry metrics)))
