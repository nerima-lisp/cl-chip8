# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-10-26

### Added

- Added platform profiles for `:cosmac-vip`, `:modern`, `:schip`,
  `:schip-legacy`, and `:xo-chip`, including SUPER-CHIP and XO-CHIP
  instructions. `:cosmac-vip` and `:modern` default to 4 KiB, support only
  `:lores`, and report the `:chip8` font set. `:schip` and `:schip-legacy` also
  default to 4 KiB, while `:xo-chip` defaults to 64 KiB; these three platforms
  support both `:lores` and `:hires` and report the `:chip8` and `:schip-large`
  font sets. Default tickrates, in instructions per frame, are 15 for
  `:cosmac-vip`, 12 for `:modern`, 30 for `:schip` and `:schip-legacy`, and
  100 for `:xo-chip`. Multiply by 60 to get instructions per second. CPU-rate
  precedence is CLI, TOML, ROM-specific metadata, ROM database platform
  metadata, then the selected platform's tickrate. An embedding application's
  supplied default applies after these; otherwise the final fallback is 700
  instructions per second.
- Added SHA-1 ROM database lookup and supported-platform mappings for
  `originalChip8`, `modernChip8`, `chip48`, `superchip1`, `superchip`, and
  `xochip`. Matched records can provide platform-specific quirks, tickrate,
  and pixel colors. Unsupported upstream platforms signal
  `chip8-unsupported-platform` before the terminal session starts unless the
  CLI explicitly supplies `--platform` or `--quirks`. `--platform` selects
  machine defaults and capabilities; `--quirks` selects instruction behavior
  and does not change the selected platform.
- Added CLI `--platform`, `--quirks`, `--config`, `--clock-hz`, `--audio`, and
  `--colors-pixels` behavior for platform profiles, TOML configuration, audio
  output, and palette selection. TOML adds `platform`, `lores_sprite`,
  `collision`, `lores_scroll`, and `mode_switch_clear` settings alongside the
  existing quirk controls.
- Added PCM audio through `cl-audio-kit` v0.1.1, with CLI modes `auto`,
  `pcm`, `bell`, and `off`. CLI `auto` falls back to the terminal bell if the
  output device cannot be opened. Audio worker stop, stream abort, and stream
  close use one-second waits; streams are closed after an abort. Direct Common
  Lisp calls default to audio off.
- Added adaptive terminal rendering for low and high resolutions. High
  resolution selects half-block, quarter-block, or braille output from the
  available terminal size; the application pauses instruction stepping while
  the terminal is below the minimum size for the selected resolution. The
  [Terminal guide](docs/src/guide/terminal.md) lists each renderer's minimum
  terminal size.
- Added Timendus conformance coverage and optional chip8Archive corpus
  compatibility checks. The Nix check supplies both ROM sets and verifies
  generated ROM database data against the checked-in file.
- Added a realtime pacing benchmark and CI jobs for realtime measurements.
  Measurement jobs run only on pushes to `verify/**` and `workflow_dispatch` events.
  CI also compiles `bench/realtime.lisp` under a compiler-warning gate.
- Added the `chip8-platform` type, `chip8-platform-p`, `find-chip8-platform`, and
  the `chip8-platform-name`, `chip8-platform-memory-size`,
  `chip8-platform-resolutions`, `chip8-platform-font-sets`,
  `chip8-platform-default-tickrate`, and `chip8-platform-default-quirks`
  readers. Added `chip8-machine-platform`, `chip8-machine-memory-size`,
  `chip8-machine-resolution`, `set-chip8-machine-resolution!`,
  `chip8-machine-logical-width`, `chip8-machine-logical-height`,
  `chip8-machine-plane-mask`, and `set-chip8-machine-plane-mask!`. Added the
  `+maximum-memory-size+`, `+physical-display-width+`, and
  `+physical-display-height+` constants.

### Changed

- Updated `cl-tty-kit` to v1.7.3 for deadline pacing, hybrid waiting, and
  adaptive spinning.
- Unmatched ROMs larger than the 4 KiB machine's 3,584-byte ROM capacity now
  infer XO-CHIP unless CLI or TOML explicitly selects a platform.
- **Breaking:** `make-chip8-machine` accepts `:platform` (`:cosmac-vip`, `:modern`, `:schip`,
  `:schip-legacy`, or `:xo-chip`) and optional `:memory-size` of 4096 or 65536;
  either size can override any platform's default. `:quirks` still overrides
  the platform default. Use
  `(make-chip8-machine :platform :xo-chip)` for a 64 KiB machine.
  `chip8-machine-platform` and
  `chip8-machine-memory-size` return the selected platform and actual capacity.
  `chip8-machine-quirks` now reflects the selected platform's default when
  `:quirks` is omitted. Machines start in `:lores` resolution.
- **Breaking:** `chip8-machine-memory`, `load-bytes-into-memory`, `memory-read`, `load-rom`,
  and `load-rom-file` use the machine's 4 KiB or 64 KiB capacity.
  `chip8-machine-pc` and entries in `chip8-machine-stack` now store 16-bit
  addresses, and `chip8-wait-state-pc` is exported with the same range.
  `check-memory-access` now takes
  `(machine address span)`. Replace fixed 4096-byte checks with
  `chip8-machine-memory-size`; ROMs loaded at `+rom-load-address+` can use at
  most the machine capacity minus `#x200`. `check-memory-access`'s `span` is
  the access length in bytes. The exported `+memory-size+` remains 4096; use
  `chip8-machine-memory-size` for the selected machine's capacity.
- **Breaking:** The `chip8-framebuffer` type now describes a two-dimensional
  `(unsigned-byte 2)` array. The `chip8-framebuffer` and
  `chip8-framebuffer-snapshot` functions return a two-dimensional snapshot
  sized for the current logical resolution, with plane 1 in bit 0 and plane 2
  in bit 1. `chip8-machine-framebuffer` exposes the physical 128×64 array;
  `+physical-display-width+` and
  `+physical-display-height+` report its dimensions.
  `chip8-machine-resolution` and `set-chip8-machine-resolution!` read and set
  the resolution; `chip8-machine-logical-width` and `chip8-machine-logical-height`
  report its dimensions. `chip8-machine-plane-mask` and
  `set-chip8-machine-plane-mask!` read and set the selected planes;
  `display-reset!` clears all planes in the physical display. `chip8-reset!`
  resets the resolution to `:lores` and the mask to 1. `display-pixel-value` and
  `display-xor-pixel!` now use logical coordinates and the current plane mask,
  with an optional mask argument. Replace fixed snapshot dimensions with
  `chip8-machine-logical-width` and `chip8-machine-logical-height`; test a plane
  with `(logbitp 0 (aref frame y x))` for plane 1 or
  `(logbitp 1 (aref frame y x))` for plane 2, where `frame` is a snapshot
  array. `+display-width+` and
  `+display-height+`
  remain the 64×32 lores dimensions.

### Fixed

- Flush pending Escape input when no more input arrives for 100 ms, so a lone
  Escape key exits after the decoder timeout.
- Fixed a test hang on Darwin in the CLI timeout regression test.

## [0.2.1] - 2026-10-02

### Changed

- Synchronized framebuffer snapshots and display updates.
- Kept COSMAC VIP display-wait drawing before the vblank wait, with direct
  regression coverage for the completed framebuffer.

### Fixed

- Preserved logger streams when logger creation or flushing fails.
- Retired render executors and channels when pipeline initialization fails.
- Corrected logical-op and arithmetic VF handling, VIP VF reset behavior, app
  pause cleanup, and rendering retirement after worker timeouts.

## [0.2.0] - 2026-09-30

### Added

- Added terminal control flow, configuration, structured logging, metrics,
  headless execution, framebuffer rendering, and the Timendus conformance
  suite.

### Changed

- Rebuilt the machine and rendering state around explicit Common Lisp APIs.
- Added CHIP-8 compatibility profiles and expanded the supported Nix systems.

### Fixed

- Corrected opcode boundary handling, display-wait timing, sprite origins, and
  application lifecycle behavior.

## [0.1.2] - 2026-08-10

### Changed

- Reduced rendering overhead and documented rendering performance invariants.

## [0.1.1] - 2026-08-10

### Fixed

- Corrected documentation for symbols that are not exported.
- Anchored playfield placement to literal coordinates and sanitized corpus
  names in tests.

## [0.1.0] - 2026-08-10

Initial release.
