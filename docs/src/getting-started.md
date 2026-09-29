# Getting Started

cl-chip8 runs CHIP-8 ROMs in a terminal. It supports SBCL and is packaged as
a Nix flake.

## Prerequisites

- **SBCL.** The implementation is SBCL-only.
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

The command takes one required ROM path. Use `--clock-hz` for a positive
instruction rate, `--quirks` to select `modern` or `cosmac-vip`, `--config` to
load a TOML configuration file, and `--log` to select a logging destination or
level. See the [Terminal guide](guide/terminal.md) for keyboard controls,
rendering, and exit codes.

## Add the flake input

From a consuming flake, point at the released tag:

```nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.2.0";
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
inherited configuration. You can configure the same registry from Lisp:

```lisp
(asdf:initialize-source-registry
 '(:source-registry
   (:tree "/path/to/checkouts/")
   :ignore-inherited-configuration))
```

The direct runtime dependencies are `cl-tty-kit`, `cl-dataflow-kit`, `cl-cli`,
`cl-toml-kit`, `cl-log-kit`, `cl-observability-kit`, `cl-concurrent-kit`,
`cl-date-kit`, and `cl-host-kit`. Make each dependency available through the
registry before loading the system.

## Run a ROM from Lisp

```lisp
(asdf:load-system "cl-chip8")
(cl-chip8:run :rom-path #p"/path/to/rom.ch8")
```

`run` creates a fresh machine, initializes its memory, fontset, display, and
keypad, loads the ROM at `0x200`, and enters the terminal loop. It returns a
`chip8-app` after the session ends. Runtime errors captured by the application
are available through `cl-chip8:chip8-app-error`. ROM loading errors are
signaled before the terminal session starts.

## Next steps

- Learn the machine state and execution boundary in [Core Concepts](guide/core-concepts.md).
- See keyboard, rendering, controls, and CLI behavior in the [Terminal guide](guide/terminal.md).
- Check instruction behavior, profiles, and platform limits in [Compatibility](reference/compatibility.md).
