# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

- The `:cosmac-vip` and `:modern` platforms default to 4 KiB, support only
  `:lores`, and report the `:chip8` font set. `:schip` and `:schip-legacy`
  also default to 4 KiB; `:xo-chip` defaults to 64 KiB. These three platforms
  support both `:lores` and `:hires` and report the `:chip8` and `:schip-large`
  font sets. Platform profiles expose default tickrates, measured in instructions
  per frame: 15 for `:cosmac-vip`, 12 for `:modern`, 30 for `:schip` and
  `:schip-legacy`, and 100 for `:xo-chip`. These metadata values are separate
  from the configuration's `clock_hz`, whose default remains 700 instructions
  per second.

### Changed

- `make-chip8-machine` accepts `:platform` (`:cosmac-vip`, `:modern`, `:schip`,
  `:schip-legacy`, or `:xo-chip`) and optional `:memory-size` of 4096 or 65536;
  either size can override any platform's default. `:quirks` still overrides
  the platform default. Use
  `(make-chip8-machine :platform :xo-chip)` for a 64 KiB machine.
  `chip8-machine-platform` and
  `chip8-machine-memory-size` return the selected platform and actual capacity.
  `chip8-machine-quirks` now reflects the selected platform's default when
  `:quirks` is omitted. Machines start in `:lores` resolution.
- `chip8-machine-memory`, `load-bytes-into-memory`, `memory-read`, `load-rom`,
  and `load-rom-file` use the machine's 4 KiB or 64 KiB capacity.
  `chip8-machine-pc` and entries in `chip8-machine-stack` now store 16-bit
  addresses, and `chip8-wait-state-pc` is exported with the same range.
  `check-memory-access` now takes
  `(machine address span)`. Replace fixed 4096-byte checks with
  `chip8-machine-memory-size`; ROMs loaded at `+rom-load-address+` can use at
  most the machine capacity minus `#x200`. `check-memory-access`'s `span` is
  the access length in bytes. `+memory-size+` remains 4096.
- The `chip8-framebuffer` type now describes a two-dimensional
  `(unsigned-byte 2)` array. `chip8-framebuffer` and
  `chip8-framebuffer-snapshot` return a two-dimensional snapshot sized for the
  current logical resolution, with plane 1 in bit 0 and plane 2 in bit 1.
  `chip8-machine-framebuffer` exposes the physical 128×64 array;
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
