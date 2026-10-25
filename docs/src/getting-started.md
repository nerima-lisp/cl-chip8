# Getting Started

cl-chip8 runs CHIP-8, SUPER-CHIP, and XO-CHIP ROMs in a terminal. It supports
SBCL and is packaged as a Nix flake.

## Prerequisites

- **SBCL for direct ASDF use.** The Nix package supplies the runtime on its
  supported systems. The implementation itself is SBCL-only.
- **Nix on a supported system.** The flake provides `x86_64-linux` and
  `aarch64-darwin` outputs. On other systems, load the system through SBCL and
  ASDF directly or use a Nix remote builder.
- **A live terminal.** `run` enters raw mode on the alternate screen, so it is
  not usable from a script with redirected terminal input or output.

## Run a ROM from the command line

From a checkout:

```sh
nix run .#cl-chip8 -- path/to/rom.ch8
```

Select a machine with `--platform modern`, `--platform cosmac-vip`,
`--platform schip`, `--platform schip-legacy`, or `--platform xo-chip`.
`--quirks` accepts the same five profile names and selects instruction
compatibility behavior. `--clock-hz` sets the positive CPU instruction rate;
the timers remain at 60 Hz. `--config` loads a TOML configuration file,
`--colors-pixels` overrides the display palette, `--audio` selects audio
output, and `--log` writes JSON log records to a file. See the
[Terminal guide](guide/terminal.md) for source priority, controls, rendering,
audio behavior, and exit codes.

For a ROM recognized by the bundled ROM database, the database supplies a
supported platform and profile when no higher-priority platform is selected.
If its known upstream platform is unsupported, startup reports that platform
unless `--platform` or `--quirks` was supplied explicitly. Database settings
also provide ROM-specific quirks, clock metadata, and colors where applicable.

## Add the flake input

From a consuming flake, point at the latest released tag:

```nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.2.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

While developing against an unreleased change, use
`path:../cl-chip8` and point it at a local checkout.

## Load the system with ASDF

Declare the dependency in your system:

```lisp
(defsystem "my-chip8-tool"
  :depends-on ("cl-chip8"))
```

ASDF must be able to find `cl-chip8` and its dependencies. Inside the Nix
development shell, `CL_SOURCE_REGISTRY` is configured for you:

```sh
nix develop
```

Outside Nix, point the registry at the parent directory that contains the
checkout and its sibling dependencies:

```sh
export CL_SOURCE_REGISTRY="/path/to/checkouts//:"
```

The trailing `//` searches recursively and the trailing `:` preserves the
inherited configuration. In a fresh SBCL session, load ASDF before evaluating
ASDF package-qualified forms. You can configure the same registry from Lisp:

```lisp
(require :asdf)
(asdf:initialize-source-registry
 '(:source-registry
   (:tree "/path/to/checkouts/")
   :ignore-inherited-configuration))
```

The direct runtime dependencies include `cl-tty-kit`, `cl-dataflow-kit`,
`cl-cli`, `cl-toml-kit`, `cl-log-kit`, `cl-observability-kit`,
`cl-concurrent-kit`, `cl-date-kit`, `cl-host-kit`, `cl-crypto-kit`, and
`cl-audio-kit`. Nix pins and supplies these dependencies. Outside Nix, make
their source trees available through the registry before loading the system;
the flake lists the pinned source repositories. PCM audio outside Nix also
requires the PortAudio shared library: install it on the system or set
`CL_AUDIO_KIT_PORTAUDIO_LIBRARY` to its full path. The Nix launcher sets this
variable automatically.

## Run a ROM from Lisp

```lisp
(require :asdf)
(asdf:load-system "cl-chip8")
(cl-chip8:run :rom-path #p"/path/to/rom.ch8" :audio-mode :off)
```

`run` creates a fresh machine using `:platform` (default `:modern`) and an
optional `chip8-quirks` value, initializes its memory, font sets, display, and
keypad, loads the ROM at `0x200`, then enters the terminal loop. Unlike the
CLI's default `auto` audio mode, the Lisp API defaults to `:off`; select
`:pcm`, `:bell`, or `:auto` with `:audio-mode` when needed. It returns a
`chip8-app` after the session ends. Runtime errors captured by the application
are available through `cl-chip8:chip8-app-error`. ROM loading and unsupported
platform errors are signaled before the terminal session starts.

## Next steps

- Learn the machine state and execution boundary in [Core Concepts](guide/core-concepts.md).
- See keyboard, adaptive rendering, controls, and CLI behavior in the [Terminal guide](guide/terminal.md).
- Check the platform profiles, instruction behavior, ROM database, and limits in [Compatibility](reference/compatibility.md).
- Review API changes and migration notes in the [changelog](https://github.com/nerima-lisp/cl-chip8/blob/main/CHANGELOG.md).
