# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-10-02

### Changed

- Synchronized framebuffer snapshots and display updates, and made render
  pipeline startup and logger cleanup exception-safe.
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
