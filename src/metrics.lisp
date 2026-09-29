;;;; Metrics boundary for the CHIP-8 application.

(in-package #:cl-chip8)

(declaim (notinline chip8-render-state-frame-count
                    chip8-render-pipeline-state
                    chip8-render-pipeline-submitted-rows
                    chip8-render-pipeline-serial-rows))

(defstruct (chip8-metrics (:constructor %make-chip8-metrics))
  registry
  counters
  pending
  applied)

(defvar *chip8-metrics* nil)

(defun %chip8-observability-function (name)
  (%chip8-package-function "CL-OBSERVABILITY-KIT" name))

(defun %chip8-observability-macro-symbol (name)
  (let* ((package (find-package "CL-OBSERVABILITY-KIT"))
         (symbol (and package (find-symbol name package))))
    (unless (and symbol (macro-function symbol))
      (error "Required CL-OBSERVABILITY-KIT::~A macro is unavailable." name))
    symbol))

(defun %define-chip8-metric (registry name help kind unit)
  ;; DEFINE-COUNTER is intentionally evaluated only during setup.  Runtime
  ;; command paths update the local pending table, never the external metric.
  (eval (list (%chip8-observability-macro-symbol
               (if (eq kind :gauge) "DEFINE-GAUGE" "DEFINE-COUNTER"))
              registry (intern name (find-package "CL-CHIP8"))
              :help help
              :unit unit)))

(defun %chip8-metric-for (metrics name)
  (or (gethash name (chip8-metrics-counters metrics))
      (error "Unknown CHIP-8 metric ~S." name)))

(defun %chip8-metric-of-kind (metrics name kind)
  "Return the registered metric NAME, signalling unless it is of KIND.

  cl-observability-kit rejects a mis-kinded operation too, but only once
  FLUSH reaches it, by which point the wrong value is already in the pending
  table and the failure names FLUSH rather than the call that caused it."
  (let* ((metric (%chip8-metric-for metrics name))
         (actual (funcall (%chip8-observability-function "METRIC-KIND") metric)))
    (unless (eq actual kind)
      (error "CHIP-8 metric ~A is a ~A, not a ~A." name actual kind))
    metric))

(defun make-chip8-metrics ()
  (let* ((make-registry (%chip8-observability-function "MAKE-METRIC-REGISTRY"))
         (registry (funcall make-registry :scope-name "cl-chip8"))
         (counters (make-hash-table :test #'equal))
         (pending (make-hash-table :test #'equal)))
    (dolist (spec '(("chip8_instructions_total" "Executed CHIP-8 instructions." :counter nil)
                    ("chip8_effective_hz" "Effective instruction rate." :gauge "Hz")
                    ("chip8_render_frames_total" "Rendered frames." :counter nil)
                    ("chip8_render_rows_worker_total" "Rendered rows in workers." :counter nil)
                    ("chip8_render_rows_serial_total" "Rendered rows serially." :counter nil)))
      (setf (gethash (first spec) counters)
            (%define-chip8-metric registry
                                  (first spec) (second spec) (third spec) (fourth spec))
            (gethash (first spec) pending) 0))
    (%make-chip8-metrics :registry registry
                         :counters counters
                         :pending pending
                         :applied (make-hash-table :test #'equal))))

(defun chip8-metric-add (metrics name &optional (amount 1))
  "Queue AMOUNT for the counter NAME.  No cl-observability-kit operation occurs here."
  (check-type metrics chip8-metrics)
  (%chip8-metric-of-kind metrics name :counter)
  (incf (gethash name (chip8-metrics-pending metrics)) amount))

(defun chip8-metric-set (metrics name value)
  "Queue the absolute gauge VALUE, not an increment.  No operation occurs here."
  (check-type metrics chip8-metrics)
  (%chip8-metric-of-kind metrics name :gauge)
  (setf (gethash name (chip8-metrics-pending metrics)) value))

(defun flush-chip8-metrics! (metrics)
  "Apply every pending value once: counters through METRIC-INC, gauges through METRIC-SET.

A zero pending value is published rather than skipped, so a counter that never
moved reports zero and a gauge cleared to zero does not keep its old reading."
  (check-type metrics chip8-metrics)
  (let ((metric-inc (%chip8-observability-function "METRIC-INC"))
        (metric-set (%chip8-observability-function "METRIC-SET"))
        (metric-kind (%chip8-observability-function "METRIC-KIND"))
        (pending (chip8-metrics-pending metrics)))
    (maphash (lambda (name metric)
               (let ((value (gethash name pending 0)))
                 (ecase (funcall metric-kind metric)
                   (:counter (funcall metric-inc metric value))
                   (:gauge (funcall metric-set metric value)))
                 (setf (gethash name pending) 0)))
             (chip8-metrics-counters metrics)))
  metrics)

(defun %chip8-queue-absolute-counter (metrics name value)
  "Queue the change from the last applied reading of the counter NAME to VALUE.

FINALIZE reads absolute values while a counter is published with an increment,
so re-reading the same value has to queue nothing.  That is what makes FINALIZE
idempotent and safe to call once per tick."
  (let* ((applied (chip8-metrics-applied metrics))
         (previous (gethash name applied 0)))
    (setf (gethash name applied) value)
    (let ((delta (- value previous)))
      (unless (zerop delta)
        (chip8-metric-add metrics name delta)))))

(defun finalize-chip8-metrics! (metrics
                                &key machine instructions effective-hz render-state render-pipeline)
  "Apply the run's metrics once, from the termination boundary.

MACHINE supplies the instruction count when INSTRUCTIONS is not given,
RENDER-STATE or RENDER-PIPELINE supplies the frame count, and
RENDER-PIPELINE's existing row counters supply the two row counters. Either
source may be NIL, in which case its metrics are left at zero."
  (check-type metrics chip8-metrics)
  (when machine
    (setf instructions (chip8-machine-instructions machine)))
  (when instructions
    (%chip8-queue-absolute-counter metrics "chip8_instructions_total" instructions))
  (when effective-hz
    (chip8-metric-set metrics "chip8_effective_hz" effective-hz))
  (let ((frame-count (if render-pipeline
                        (chip8-render-state-frame-count
                         (chip8-render-pipeline-state render-pipeline))
                        (and render-state
                             (chip8-render-state-frame-count render-state)))))
    (when frame-count
      (%chip8-queue-absolute-counter metrics "chip8_render_frames_total"
                                     frame-count)))
  (when render-pipeline
    (%chip8-queue-absolute-counter
     metrics "chip8_render_rows_worker_total"
     (chip8-render-pipeline-submitted-rows render-pipeline))
    (%chip8-queue-absolute-counter
     metrics "chip8_render_rows_serial_total"
     (chip8-render-pipeline-serial-rows render-pipeline)))
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
