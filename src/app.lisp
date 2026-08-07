;;;; src/app.lisp -- the thin real-IO loop, mirroring cl-nyancat's own
;;;; src/app.lisp split: everything below does real terminal I/O (reading
;;;; *STANDARD-INPUT*, driving cl-tty-kit's realtime tick loop), which is why
;;;; this file, like cl-nyancat's, has no test in t/ -- there is nothing left
;;;; in it that a real terminal is not required to exercise.
;;;;
;;;; Unlike cl-nyancat's WORLD, this application's actual CPU/display state
;;;; lives entirely in *RULEBASE*/*MEMORY*/*DISPLAY* (stage 1's globals), not
;;;; in the per-tick STATE value TICK-LOOP-RUN-REALTIME threads through
;;;; ADVANCE/RENDER/STOP. CHIP8-APP below only carries what the realtime loop
;;;; itself needs: the renderer, the input decoder, the configured clock
;;;; speed, and the quit flag a q/Q/Ctrl-C key event sets.
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
  "Runtime state for the realtime tick loop. The actual CHIP-8 machine state
(registers, memory, display, timers, keys) lives in *RULEBASE*/*MEMORY*/
*DISPLAY*, not here -- this struct only carries what the loop's own
plumbing needs. ERROR is nil for a normal run; %ADVANCE-CHIP8! sets it (and
QUITP) when EXECUTE-INSTRUCTION! signals mid-run, e.g. for a malformed ROM --
see %ADVANCE-CHIP8!'s HANDLER-CASE and cli.lisp's %RUN-HANDLER, which reports
it once RUN has returned and the terminal is already restored."
  renderer
  decoder
  (clock-hz +default-clock-hz+ :type (integer 1 *))
  (quitp nil :type boolean)
  (error nil :type (or null condition)))

(defparameter +quit-characters+ (list #\q #\Q)
  "Characters that set CHIP8-APP-QUITP on a decoded :CHARACTER event, by
application convention (q/Q), mirroring cl-nyancat's own quit-key binding.")

(defun quit-key-event-p (event)
  "True when the decoded cl-tty-kit KEY-EVENT EVENT should stop the emulator:
a :CHARACTER event whose code is in +QUIT-CHARACTERS+, or the :SPECIAL
:CONTROL-C event Ctrl-C decodes to under raw mode (ISIG is cleared, so
Ctrl-C arrives as input rather than SIGINT -- see cl-nyancat's own
src/input.lisp for the identical reasoning)."
  (or (and (eq (key-event-type event) :character)
           (member (key-event-code event) +quit-characters+ :test #'char=))
      (and (eq (key-event-type event) :special) (eq (key-event-code event) :control-c))))

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
decoded cl-tty-kit KEY-EVENTs, or NIL when nothing was available."
  (let ((chunk (%read-available-string stream)))
    (when (plusp (length chunk))
      (decode-input-chunk decoder chunk))))

(defun %instructions-per-tick (clock-hz)
  "Return the number of CPU instructions to execute in one 1/60-second tick at
CLOCK-HZ, per the brief: (round clock-hz 60), floored at 1 so a very low
--clock-hz still makes progress."
  (max 1 (round clock-hz 60)))

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
  "One tick: poll input, run this tick's share of CPU instructions, then step
the timers and the keypad's hold countdowns once. Returns APP, mutated in
place -- see this file's header comment on where the real CHIP-8 state
lives.

The CPU-execution step is wrapped in a HANDLER-CASE: a malformed ROM can make
EXECUTE-INSTRUCTION! signal CHIP8-INVALID-OPCODE, CHIP8-STACK-OVERFLOW/
-UNDERFLOW, or CHIP8-MEMORY-ACCESS-OUT-OF-BOUNDS (see opcodes.lisp/
memory.lisp) at any point mid-run. Catching it HERE, rather than letting it
propagate out of TICK-LOOP-RUN-REALTIME, means the loop stops the same way a
normal quit does -- by this function returning normally and
%CHIP8-APP-FINISHED-P then seeing QUITP set -- so RUN's enclosing
WITH-RAW-MODE/WITH-TERMINAL-SESSION unwind and restore the terminal on an
ordinary, successful return from their body, never on a non-local exit
through them. A bare ERROR clause is also caught, as defense in depth against
a condition this package did not anticipate; either way the condition is
stashed on APP-ERROR for %RUN-HANDLER to report once the terminal is back to
normal, instead of an uncaught backtrace being dumped into a raw-mode
terminal."
  (%apply-key-events! app (%poll-input-events (chip8-app-decoder app) *standard-input*))
  (handler-case
      (dotimes (i (%instructions-per-tick (chip8-app-clock-hz app)))
        (execute-instruction!))
    (chip8-error (condition)
      (setf (chip8-app-error app) condition)
      (setf (chip8-app-quitp app) t))
    (error (condition)
      (setf (chip8-app-error app) condition)
      (setf (chip8-app-quitp app) t)))
  (step-timers!)
  (keypad-step!)
  app)

(defun %render-chip8-app! (app)
  "Render one frame for APP: blit *DISPLAY* and the sound indicator into the
renderer's back buffer, then emit the diff. Returns the frame TICK-LOOP-RUN-
REALTIME should write (see RENDERER-RENDER's contract)."
  (render-chip8! (renderer-screen (chip8-app-renderer app)))
  (renderer-render (chip8-app-renderer app)))

(defun %chip8-app-finished-p (app)
  (chip8-app-quitp app))

(defun run (&key rom-path (clock-hz +default-clock-hz+) (stream *standard-output*))
  "Load the ROM at ROM-PATH, reset the machine, and run it live in the
terminal until q, Q, or Ctrl-C. CLOCK-HZ is the target CPU instructions per
second; timers always step at a fixed 60Hz regardless. The terminal is put in
raw mode on the alternate screen with the cursor hidden, and restored on the
way out. Returns the final CHIP8-APP."
  (reset-cpu-state!)
  (memory-reset!)
  (display-reset!)
  (load-fontset-into-memory!)
  (load-rom-file! rom-path)
  (keypad-reset!)
  (let ((app (make-chip8-app :renderer (make-renderer +screen-width+ +screen-height+)
                             :decoder (make-input-decoder)
                             :clock-hz clock-hz)))
    (with-raw-mode ()
      (with-terminal-session (session-stream :stream stream :hide-cursor t :alternate-screen t)
        (tick-loop-run-realtime
         app
         #'%advance-chip8!
         #'%render-chip8-app!
         #'%chip8-app-finished-p
         :stream session-stream
         :interval 1/60)))
    app))
