(in-package #:cl-user)
(defpackage #:cl-chip8
  (:use #:cl)
  (:import-from #:cl-dataflow-kit
                #:define-state-machine
                #:make-state-machine
                #:step-state-machine
                #:state-machine-state
                #:invalid-transition-error)
  (:import-from #:cl-date-kit
                #:duration
                #:duration-of-seconds
                #:duration-to-seconds)
  (:import-from #:cl-tty-kit #:key-event-type #:key-event-code #:key-event-kind #:make-input-decoder #:decode-input #:decode-input-chunk #:make-renderer #:renderer-screen #:renderer-render #:renderer-resize #:screen-write-string #:with-screen-batch #:make-style #:with-raw-mode #:with-terminal-session #:tick-loop-run-realtime)
  (:import-from #:cl-cli #:make-app #:make-option #:make-positional #:run-app #:option-value #:positional-value #:current-process-argv)
  (:import-from #:cl-concurrent-kit #:make-executor #:shutdown-executor #:submit #:make-channel #:make-semaphore #:send #:try-send #:recv #:close-channel #:wait-on-semaphore #:signal-semaphore #:executor-queue-depth #:executor-high-water-mark #:make-atomic-counter #:atomic-counter-value #:atomic-counter-incf #:make-lock #:with-lock-held)
  (:import-from #:host-kit #:quit)
  (:export #:chip8-error #:chip8-rom-too-large #:chip8-rom-too-large-size #:chip8-rom-too-large-available #:chip8-rom-short-read #:chip8-rom-short-read-actual-size #:chip8-rom-short-read-expected-size #:chip8-invalid-opcode #:chip8-invalid-opcode-opcode #:chip8-stack-overflow #:chip8-stack-overflow-depth #:chip8-stack-underflow #:chip8-memory-access-out-of-bounds #:chip8-memory-access-out-of-bounds-address #:chip8-memory-access-out-of-bounds-span #:chip8-rom-not-regular-file #:chip8-rom-not-regular-file-path #:chip8-cps-error #:chip8-cps-error-phase #:chip8-cps-error-cause
   #:+memory-size+ #:+rom-load-address+ #:+register-count+ #:+initial-pc+ #:+call-stack-limit+ #:+display-width+ #:+display-height+ #:+fontset-address+ #:+chip8-fontset+
   #:chip8-machine #:chip8-machine-p #:make-chip8-machine #:chip8-reset! #:chip8-machine-memory #:chip8-machine-v #:chip8-machine-register #:chip8-machine-i #:chip8-machine-pc #:chip8-machine-sp #:chip8-machine-stack #:chip8-machine-delay-timer #:chip8-machine-sound-timer #:chip8-machine-keypad #:chip8-machine-framebuffer #:chip8-machine-quirks #:chip8-machine-waiting #:chip8-machine-instructions
   #:chip8-quirks #:chip8-quirks-p #:make-chip8-quirks #:merge-chip8-quirks #:chip8-quirks-profile #:chip8-quirks-vf-behavior #:chip8-quirks-memory-i #:chip8-quirks-display-wait #:chip8-quirks-clipping #:chip8-quirks-shift-source #:chip8-quirks-bnnn-register #:chip8-quirks-fx0a-completion
   #:memory-reset! #:load-bytes-into-memory #:check-memory-access #:memory-read #:load-fontset-into-memory! #:display-reset! #:display-pixel-value #:display-xor-pixel! #:chip8-framebuffer #:chip8-framebuffer-snapshot #:execute-instruction! #:fetch-opcode #:step-timers! #:sound-timer-active-p #:keypad-reset! #:key-down-p #:pressed-keys #:chip8-key-down! #:chip8-key-up! #:load-rom #:load-rom-file
   #:chip8-run-result #:chip8-run-result-status #:chip8-run-result-executed #:chip8-run-result-machine #:chip8-run-result-continuation #:chip8-run-instructions #:chip8-run-ticks #:chip8-resume! #:render-chip8! #:render-chip8-concurrently! #:run
   #:chip8-control-event #:chip8-control-event-p #:make-chip8-control-event #:chip8-control-event-type #:chip8-control-event-payload
   #:*chip8-state-machine-definition* #:make-chip8-control-state-machine #:chip8-control-state #:step-chip8-control-state
   #:chip8-app #:chip8-app-p #:make-chip8-app #:chip8-app-machine #:chip8-app-state-machine
   #:chip8-app-renderer #:chip8-app-decoder #:chip8-app-render-pipeline #:chip8-app-clock-hz
   #:chip8-app-quit-p #:chip8-app-error #:chip8-app-instruction-remainder #:chip8-app-paused-p #:chip8-app-started-at
   #:chip8-run-result #:chip8-run-result-status #:chip8-run-result-executed #:chip8-run-result-machine #:chip8-run-result-continuation #:chip8-run-instructions #:chip8-run-ticks #:chip8-resume! #:render-chip8! #:render-chip8-concurrently! #:run
   #:chip8-run-result #:chip8-run-result-status #:chip8-run-result-executed #:chip8-run-result-machine #:chip8-run-result-continuation #:chip8-run-instructions #:chip8-run-ticks #:chip8-resume! #:render-chip8! #:render-chip8-concurrently! #:with-chip8-render-pipeline #:+screen-width+ #:+screen-height+ #:run
   #:chip8-config-error #:chip8-config-error-source-name #:chip8-config-error-line #:chip8-config-error-column #:chip8-config-error-path #:chip8-config-error-key #:chip8-config-error-reason
   #:chip8-config #:chip8-config-rom-path #:chip8-config-clock-hz #:chip8-config-quirks #:chip8-config-log-path #:merge-chip8-config #:load-chip8-config-file #:make-chip8-config-from-sources
   #:make-chip8-logger #:close-chip8-logger #:chip8-log #:chip8-log-info #:chip8-log-error #:flush-chip8-logger
   #:chip8-metrics #:make-chip8-metrics #:chip8-metric-add #:chip8-metric-set #:record-chip8-instruction! #:flush-chip8-metrics! #:finalize-chip8-metrics! #:chip8-metrics-snapshot #:chip8-metrics-fields
   #:chip8-run-options #:*app* #:main #:image-entry-point))

(in-package #:cl-chip8)
(declaim (notinline chip8-machine-instructions))
