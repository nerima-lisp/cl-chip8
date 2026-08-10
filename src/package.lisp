;;;; src/package.lisp -- the sole DEFPACKAGE form for this repository.
;;;;
;;;; CODING_STANDARD.md requires `:use` to name only #:cl and every sibling
;;;; package to come in through `:import-from`, so the import list below is
;;;; the price of that rule, not an oversight.
;;;;
;;;; Stage 1 built the CPU state core: the Prolog rulebase of dynamic facts
;;;; (state.lisp), the memory and display arrays and their foreign
;;;; predicates (memory.lisp, display.lisp), and the fontset (fontset.lisp).
;;;; This stage adds the opcode rulebase (opcodes.lisp), keypad decoding
;;;; (keypad.lisp), 60Hz timer stepping (timers.lisp), ROM loading (rom.lisp),
;;;; terminal rendering (render.lisp), and the realtime app/CLI (app.lisp,
;;;; cli.lisp) -- hence the #:cl-tty-kit and #:cl-cli import-from clauses
;;;; below, added now that this stage's code needs them.
(in-package #:cl-user)

(defpackage #:cl-chip8
  (:use #:cl)
  ;; cl-prolog (L1): the rulebase container, the query API, and the
  ;; assert/retract/define-foreign-predicate primitives this package's CPU
  ;; state is built from. #:assert is deliberately NOT imported: this
  ;; package never calls it (ASSERTZ covers every insertion this stage
  ;; needs), which avoids a name clash with CL:ASSERT that would otherwise
  ;; require a :SHADOWING-IMPORT-FROM.
  ;;
  ;; IS is this stage's addition: the opcode rulebase (opcodes.lisp)
  ;; evaluates arithmetic (PC/I/register updates, BCD digits, ALU flags) via
  ;; `is/2` goals inside clause bodies. FRESH-LOGIC-VARIABLE lets a foreign
  ;; predicate build a throwaway logic variable for a retract pattern (see
  ;; LOAD-REGISTERS in opcodes.lisp) without reusing a caller-visible name.
  ;; Goal functors like `is` must come in by exact symbol identity, same as
  ;; ASSERTZ/RETRACT above: the engine's builtin dispatch matches by EQL on
  ;; the interned CL-PROLOG symbol, not by name, so a same-named
  ;; CL-CHIP8::IS the reader might otherwise intern here would silently
  ;; fail to dispatch. Arithmetic *sub-expression* operators inside an is/2
  ;; expression (+, -, mod, //, *, ...) do NOT need this treatment: cl-prolog
  ;; resolves those by STRING= on the symbol's name, so the plain CL symbols
  ;; already inherited via :USE #:CL (or even a fresh CL-CHIP8:: symbol for
  ;; a non-CL name like `//') work without any import.
  (:import-from #:cl-prolog
                #:make-rulebase
                #:query-prolog
                #:query-prolog-first
                #:prolog-succeeds-p
                #:solution-binding
                #:assertz
                #:retract
                #:retractall
                #:define-foreign-predicate
                #:unify
                #:logic-substitute
                #:is
                #:fresh-logic-variable
                ;; EXTEND-RULEBASE is the rule DSL macro opcodes.lisp uses to
                ;; add the ~35-instruction STEP rulebase on top of
                ;; *RULEBASE*. Like IS above, a macro also needs exact-symbol
                ;; import: without it, a bare `extend-rulebase' token here
                ;; would intern a fresh, unbound CL-CHIP8::EXTEND-RULEBASE
                ;; and the compiler would try to evaluate `(extend-rulebase
                ;; ...)' as an ordinary function call -- evaluating each
                ;; quoted-looking clause literal as code in the process,
                ;; which is exactly the "illegal function call" this import
                ;; was added to fix.
                #:extend-rulebase)
  ;; cl-tty-kit (L1): key-event introspection and input decoding for the
  ;; keypad (keypad.lisp), the screen/renderer/style types and tick loop for
  ;; the realtime app (render.lisp, app.lisp), and raw-mode/session
  ;; management for the real terminal app.lisp drives.
  (:import-from #:cl-tty-kit
                #:key-event-type
                #:key-event-code
                #:key-event-kind
                #:make-input-decoder
                #:decode-input
                #:decode-input-chunk
                #:make-renderer
                #:renderer-screen
                #:renderer-render
                #:renderer-resize
                #:screen-write-string
                #:with-screen-batch
                #:make-style
                #:with-raw-mode
                #:with-terminal-session
                #:tick-loop-run-realtime)
  ;; cl-cli (L1): the declarative app spec and invocation accessors cli.lisp
  ;; builds the `cl-chip8` command from.
  (:import-from #:cl-cli
                #:make-app
                #:make-option
                #:make-positional
                #:run-app
                #:option-value
                #:positional-value
                #:current-process-argv)
  ;; cl-concurrent-kit (L1): a persistent bounded worker executor and atomic
  ;; counters for the pure terminal-row rendering stage. CHIP-8 instruction
  ;; execution remains on the owner thread because its Prolog rulebase is
  ;; intentionally stateful and sequential.
  (:import-from #:cl-concurrent-kit
              #:make-executor
              #:shutdown-executor
              #:submit
              #:make-channel
              #:make-semaphore
              #:send
              #:try-send
              #:recv
              #:close-channel
              #:wait-on-semaphore
              #:signal-semaphore
              #:executor-queue-depth
              #:executor-high-water-mark
              #:make-atomic-counter
              #:atomic-counter-value
              #:atomic-counter-incf
              #:make-lock
              #:with-lock-held)
  ;; cl-date-kit supplies the native timeout type used by the persistent
  ;; render pipeline. Importing the type and conversion functions keeps the
  ;; package boundary explicit in the same way as the other sibling systems.
  (:import-from #:cl-date-kit
                #:duration
                #:duration-of-seconds
                #:duration-to-seconds)
  ;; cl-host-kit owns process termination for both the CLI entry point and
  ;; the script runners.
  (:import-from #:host-kit
                #:quit)
  ;; THE EXPORT RULE. A symbol is exported if and only if it is one of:
  ;;
  ;;   (a) an entry point that runs the emulator;
  ;;   (b) a condition, or a reader on one, that a caller must handle;
  ;;   (c) a machine-state primitive needed to drive the interpreter
  ;;       headlessly -- reset, load, step, read a pixel, read a fact;
  ;;   (d) a whole-frame render operator, a render-pipeline lifecycle
  ;;       operator, or a type named by a kept operator's CHECK-TYPE or
  ;;       returned by one.
  ;;
  ;; Everything else stays internal: Prolog goal functors, DEFSTRUCT
  ;; accessors, telemetry counters, tuning knobs, sub-step renderers,
  ;; internal bounds checks, and helpers with no CHIP-8 semantics.
  ;;
  ;; Why goal functors are internal: a functor is an implementation detail of
  ;; a rulebase whose shape this system has not committed to. The proof that
  ;; exporting them was never required is ENSURE-MEMORY-RANGE -- a
  ;; DEFINE-FOREIGN-PREDICATE at memory.lisp:79 that is NOT exported and is
  ;; called as a goal from an opcodes.lisp clause body without trouble,
  ;; because a term read inside CL-CHIP8 interns the identical symbol.
  ;; Dispatch needs symbol IDENTITY, and :IMPORT-FROM supplies identity for
  ;; an internal symbol just as well as :EXPORT does -- t/package.lisp does
  ;; exactly that, as it already did for cl-prolog's ASSERTZ and RETRACT.
  ;; :EXPORT additionally supplies a semver commitment, which is the part
  ;; that was being paid for and not used.
  (:export
   ;; -- Conditions --
   #:chip8-error
   #:chip8-rom-too-large
   #:chip8-rom-too-large-size
   #:chip8-rom-too-large-available
   #:chip8-rom-short-read
   #:chip8-rom-short-read-actual-size
   #:chip8-rom-short-read-expected-size
   #:chip8-invalid-opcode
   #:chip8-invalid-opcode-opcode
   #:chip8-stack-overflow
   #:chip8-stack-overflow-depth
   #:chip8-stack-underflow
   #:chip8-memory-access-out-of-bounds
   #:chip8-memory-access-out-of-bounds-address
   #:chip8-memory-access-out-of-bounds-span
   #:chip8-rom-not-regular-file
   #:chip8-rom-not-regular-file-path

   ;; -- Memory: the 4096-byte address space --
   #:+memory-size+
   #:+rom-load-address+
   #:*memory*
   #:memory-reset!
   #:load-bytes-into-memory

   ;; -- Display: the 64x32 monochrome framebuffer --
   ;; *DISPLAY* itself is NOT exported, unlike *MEMORY*, and the asymmetry is
   ;; deliberate. *MEMORY* is an (UNSIGNED-BYTE 8) array whose every invariant
   ;; the array type and AREF's own bounds check already enforce, so handing it
   ;; out is safe. *DISPLAY* has invariants that live OUTSIDE the array --
   ;; *DISPLAY-DIRTY-ROWS*, *DISPLAY-ROW-GENERATIONS* and *DISPLAY-LOCK* in
   ;; display-types.lisp -- and the concurrent renderer only repaints rows the
   ;; dirty set names. A caller doing (SETF (AREF *DISPLAY* Y X) 1) therefore
   ;; gets a pixel that DISPLAY-PIXEL-VALUE reports as set, RENDER-CHIP8!
   ;; paints, and RENDER-CHIP8-CONCURRENTLY! silently omits -- two exported
   ;; renderers disagreeing about identical state, with no exported way to
   ;; reconcile them. Export the self-validating primitive; withhold the one
   ;; whose invariants are external. DISPLAY-PIXEL-VALUE reads and
   ;; DISPLAY-XOR-PIXEL! writes, and the latter maintains the dirty set.
   #:+display-width+
   #:+display-height+
   #:display-reset!
   #:display-pixel-value
   #:display-xor-pixel!

   ;; -- Fontset: the 16 built-in hex-digit glyphs --
   #:+fontset-address+
   #:+chip8-fontset+
   #:load-fontset-into-memory!

   ;; -- CPU state: the Prolog rulebase and its fact shapes --
   #:*rulebase*
   #:+register-count+
   #:+initial-pc+
   #:+call-stack-limit+
   #:reset-cpu-state!
   #:key-down-p
   #:pressed-keys
   ;; Fact functors asserted/retracted against *RULEBASE* (see state.lisp):
   ;;   (v Index Value)         -- 16 general registers V0-VF
   ;;   (i-register Value)      -- the 16-bit I register
   ;;   (pc Value)              -- program counter
   ;;   (call-stack List)       -- return-address stack, most recent first
   ;;   (delay-timer Value)     -- delay timer, 0-255
   ;;   (sound-timer Value)     -- sound timer, 0-255
   ;;   (key-down Hex)          -- one fact per currently pressed hex key
   #:v
   #:i-register
   #:pc
   #:call-stack
   #:delay-timer
   #:sound-timer
   #:key-down

   ;; -- Opcodes: the instruction rulebase's execute entry point --
   ;; FETCH-OPCODE/DECODE-OPCODE are sub-steps of EXECUTE-INSTRUCTION!, and
   ;; the STEP rulebase's goal functors are internal per the rule above.
   #:execute-instruction!

   ;; -- Keypad --
   ;; KEY-EVENT->CHIP8-KEY and the KEYPAD-APPLY-* pair take a cl-tty-kit
   ;; KEY-EVENT, so they belong to the terminal layer rather than the
   ;; headless machine interface. A headless driver presses a key by
   ;; asserting a KEY-DOWN fact against *RULEBASE* and retracting it again.
   ;;
   ;; KEYPAD-STEP! is internal for a sharper reason: it is the expiry half of
   ;; a hold approximation whose arming half (KEYPAD-APPLY-KEY-EVENT! and the
   ;; *KEY-HOLD-COUNTDOWNS* table) is internal. A directly-asserted KEY-DOWN
   ;; fact has no countdown entry, so keypad.lisp's (GETHASH KEY ... 0) yields
   ;; 0, 1- takes it negative, and the very first KEYPAD-STEP! retracts the
   ;; key. Exporting the expiry without the arming would publish a pairing
   ;; that silently drops every headless keypress on its first tick.
   #:keypad-reset!

   ;; -- Timers: 60Hz delay/sound timer stepping --
   #:step-timers!

   ;; -- ROM loading --
   ;; LOAD-ROM-FILE! calls CHECK-REGULAR-ROM-FILE unconditionally, so
   ;; unexporting that predicate removes a name and not the guard.
   #:load-rom-file!

   ;; -- Rendering: half-block blit of *DISPLAY* into a cl-tty-kit SCREEN --
   ;; The two screen dimensions stay public because a caller must size the
   ;; SCREEN it hands to RENDER-CHIP8! / RENDER-CHIP8-CONCURRENTLY!, and a
   ;; wrong-sized screen clips silently rather than signalling.
   #:+screen-width+
   #:+screen-height+
   #:sound-timer-active-p
   #:render-chip8!

   ;; -- Concurrent rendering: immutable row snapshots and serial screen commit --
   ;; CHIP8-RENDER-PIPELINE is exported because concurrent-render.lisp
   ;; CHECK-TYPEs against it; without the name, a caller cannot write a
   ;; HANDLER-CASE clause for the TYPE-ERROR they can provoke.
   ;; The tuning knobs and the five telemetry counters stay internal: they
   ;; expose the batching strategy, and PARALLEL-THRESHOLD cannot even
   ;; determine behavior alone -- it is ANDed with the internal constant
   ;; +CONCURRENT-RENDER-MINIMUM-SNAPSHOTS+.
   #:chip8-render-pipeline
   #:chip8-render-pipeline-p
   #:with-chip8-render-pipeline
   #:make-chip8-render-pipeline
   #:close-chip8-render-pipeline
   #:render-chip8-concurrently!

   ;; -- App: the realtime tick loop --
   ;; RUN returns a CHIP8-APP and stores a mid-run failure on it rather than
   ;; signalling, so the type, its predicate, and the two slots that carry
   ;; the outcome are part of RUN's contract. The remaining slots are
   ;; internal wiring.
   #:chip8-app
   #:chip8-app-p
   #:chip8-app-quitp
   #:chip8-app-error
   #:run

   ;; -- CLI: the `cl-chip8' command --
   #:*app*
   #:main
   #:image-entry-point))
