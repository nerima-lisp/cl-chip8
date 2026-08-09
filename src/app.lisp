;;;; src/app.lisp -- the thin real-IO loop, mirroring cl-nyancat's own
;;;; %ADVANCE-CHIP8!'s deterministic tick logic is testable without a terminal.
;;;; The outer loop still reads *STANDARD-INPUT* and drives cl-tty-kit's realtime
;;;; raw-mode I/O, so that integration boundary is covered by real-TTY smoke tests.
;;;;
;;;; Unlike cl-nyancat's WORLD, this application's actual CPU/display state
;;;; lives entirely in the *RULEBASE*/*MEMORY*/*DISPLAY* globals, not
;;;; in the per-tick STATE value TICK-LOOP-RUN-REALTIME threads through
;;;; ADVANCE/RENDER/STOP. CHIP8-APP below only carries what the realtime loop
;;;; itself needs: the renderer, the input decoder, the configured clock
;;;; speed, and the quit flag an Escape/Ctrl-C key event sets.
;;;;
;;;; No resize polling: unlike cl-nyancat's terminal-filling animation,
;;;; CHIP-8's framebuffer is a fixed 64x32 grid (see render.lisp's
;;;; +SCREEN-WIDTH+/+SCREEN-HEIGHT+), so there is no terminal size to adapt
;;;; to -- a deliberate omission of the reference pattern's resize-polling
;;;; half, not an oversight.
(in-package #:cl-chip8)

(defparameter +default-clock-hz+ 700
  "Default CPU instructions executed per second when --clock-hz is not given.
Timers always step at 60Hz regardless of this value -- see STEP-TIMERS! and
%INSTRUCTIONS-PER-TICK below.")

(defstruct (chip8-app (:constructor make-chip8-app))
  "Runtime state for the realtime tick loop.

The actual CHIP-8 machine state (registers, memory, display, timers, keys)
lives in *RULEBASE*/*MEMORY*/*DISPLAY*, not here. This struct only carries what
the loop itself needs. INSTRUCTION-REMAINDER accumulates CPU work between 60Hz
ticks so the total scheduled work is exactly CLOCK-HZ per 60 ticks. ERROR is
nil for a normal run; %ADVANCE-CHIP8! sets it (and QUITP) when
EXECUTE-INSTRUCTION! signals mid-run, for example for a malformed ROM. Its
handler case and cli.lisp %RUN-HANDLER report the error after RUN returns and
the terminal is restored. SOUND-PULSE-REMAINDER limits terminal bell output
while the CHIP-8 sound timer is active."
  renderer
  decoder
  render-pipeline
  (clock-hz +default-clock-hz+ :type (integer 1 *))
  (instruction-remainder 0 :type (integer 0 59))
  (sound-pulse-remainder 0 :type (integer 0 5))
  (quitp nil :type boolean)
  (error nil :type (or null condition)))

(defun quit-key-event-p (event)
  "True when EVENT should stop the emulator.

EVENT is a decoded cl-tty-kit KEY-EVENT. Ctrl-C decodes to :CONTROL-C under
raw mode because ISIG is cleared, so it arrives as input rather than SIGINT."
  (and (eq (key-event-type event) :special)
       (not (null (member (key-event-code event) (list :escape :control-c))))))

(defun %read-available-string (stream)
  "Return every character currently buffered on STREAM, without blocking, as
a string. See cl-nyancat's app.lisp for why READ-CHAR-NO-HANG is the right
tool here rather than cl-tty-kit's fd-level reader."
  (with-output-to-string (out)
    (loop for char = (read-char-no-hang stream nil nil)
          while char
          do (write-char char out))))

(defun %poll-input-events (decoder stream)
  "Feed any input currently available on STREAM through DECODER, returning the
 decoded cl-tty-kit KEY-EVENTs. An empty poll flushes DECODER's pending input,
 allowing a standalone Escape to decode on the following tick."
  (let ((chunk (%read-available-string stream)))
    (if (plusp (length chunk))
        (decode-input-chunk decoder chunk)
        (cl-tty-kit:flush-input-decoder decoder))))

(defun %instructions-per-tick (app)
  "Return the CPU work for one 1/60-second tick from APP.

Retaining the integer remainder schedules exactly CLOCK-HZ instructions over
every 60 consecutive ticks, including clock rates below 60Hz."
  (multiple-value-bind
        (instructions remainder)
      (floor (+ (chip8-app-instruction-remainder app)
                (chip8-app-clock-hz app))
             60)
    (setf (chip8-app-instruction-remainder app) remainder)
    instructions))

(defun %apply-key-event! (app event)
  "Apply one decoded KEY-EVENT to APP: set CHIP8-APP-QUITP on a quit key, and
always forward it to the keypad regardless (a quit key is simply not in
+KEYPAD-MAPPING+, so KEYPAD-APPLY-KEY-EVENT! ignores it harmlessly). Returns
APP."
  (when (quit-key-event-p event)
    (setf (chip8-app-quitp app) t))
  (keypad-apply-key-event! event)
  app)

(defun %apply-key-events! (app events)
  "Apply %APPLY-KEY-EVENT! to each of EVENTS in order. Returns APP."
  (dolist (event events app)
    (%apply-key-event! app event)))

(defun %advance-chip8! (app)
  "Advance APP by one tick, mutating it in place.

Poll input, step timers, run scheduled CPU instructions unless input requested
exit, and then step keypad hold countdowns. Execution errors are saved on APP
and end the loop after terminal cleanup."
  (%apply-key-events!
    app
    (%poll-input-events (chip8-app-decoder app) *standard-input*))
  ;; A timer value written by FX15/FX18 must remain visible for this frame.
  (step-timers!)
  (unless (chip8-app-quitp app)
    (handler-case
        (loop repeat (%instructions-per-tick app)
              do (execute-instruction!))
      (error (condition)
        (setf (chip8-app-error app) condition)
        (setf (chip8-app-quitp app) t))))
  (keypad-step!)
  app)

(defun %render-chip8-app! (app)
  "Render one frame for APP, including a rate-limited terminal bell while sound is active."
  (let ((screen (renderer-screen (chip8-app-renderer app))))
    (if (chip8-app-render-pipeline app)
        (render-chip8-concurrently! screen (chip8-app-render-pipeline app))
        (render-chip8! screen)))
  (concatenate (quote string)
               (%sound-bell-prefix app)
               (renderer-render (chip8-app-renderer app))))

(defun %chip8-app-finished-p (app)
  (chip8-app-quitp app))

(defun run (&key rom-path (clock-hz +default-clock-hz+) (stream *standard-output*))
  "Load ROM-PATH, reset the machine, and run it until Escape or Ctrl-C.

CLOCK-HZ is the target CPU instructions per second; timers always step at a
fixed 60Hz regardless. The terminal is put in raw mode on the alternate
screen with the cursor hidden, and restored on the way out. Return the final
CHIP8-APP."
  (reset-cpu-state!)
  (memory-reset!)
  (display-reset!)
  (load-fontset-into-memory!)
  (load-rom-file! rom-path)
  (keypad-reset!)
  (with-chip8-render-pipeline (render-pipeline)
    (let ((app
           (make-chip8-app
             :renderer
             (make-renderer +screen-width+ +screen-height+)
             :decoder
             (make-input-decoder)
             :render-pipeline
             render-pipeline
             :clock-hz
             clock-hz)))
      (with-raw-mode
        ()
        (with-terminal-session
          (session-stream
           :stream
           stream
           :hide-cursor
           t
           :alternate-screen
           t
           :keyboard-enhancements
           10)
          (tick-loop-run-realtime
           app
           (function %advance-chip8!)
           (function %render-chip8-app!)
           (function %chip8-app-finished-p)
           :stream
           session-stream
           :interval
           1/60)))
      app)))

(defun %sound-bell-prefix (app)
  "Return a rate-limited terminal BEL while the CHIP-8 sound timer is active."
  (cond
    ((not (sound-timer-active-p))
     (setf (chip8-app-sound-pulse-remainder app) 0)
     "")
    ((zerop (chip8-app-sound-pulse-remainder app))
     (setf (chip8-app-sound-pulse-remainder app) 5)
     (string #\Bell))
    (t
     (decf (chip8-app-sound-pulse-remainder app))
     "")))
