# Getting Started

cl-chip8 runs CHIP-8 ROMs in a terminal. It supports SBCL and is packaged as a
Nix flake.

## Prerequisites

- **SBCL.** The implementation is SBCL-only.
- **`x86_64-linux` for any `nix` command.** The flake declares
  `systems = [ "x86_64-linux" ]`, so `nix run`, `nix build`, `nix develop`, and
  `nix flake check` all fail on any other system -- on macOS with `does not
  provide attribute 'packages.aarch64-darwin.<name>'`. On those hosts, load the
  system through SBCL and ASDF directly, or use an `x86_64-linux` remote
  builder.
- **A live terminal.** `run` puts the terminal into raw mode on the alternate
  screen, so it is not usable from a script with redirected I/O.

## Run a ROM from the command line

The quickest path from a checkout, on `x86_64-linux`:

```sh
nix run .#cl-chip8 -- path/to/rom.ch8
```

That builds and runs the `cl-chip8` command, which takes one required ROM path
and an optional `--clock-hz`. See the [Terminal guide](guide/terminal.md) for
the keypad layout, the command-line options, and the exit codes.

## Add the flake input

From a consuming flake, point at the released tag:

```nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.1.2";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

While developing against an unreleased change, swap the `url` for
`path:../cl-chip8` and point it at a local checkout.

## Add the system dependency

```lisp
(defsystem "my-chip8-tool"
  :depends-on ("cl-chip8"))
```

## Put the system on ASDF's source registry

Declaring the flake input does not by itself make `cl-chip8` loadable: the
input is a Nix dependency, while `asdf:load-system` resolves names through
ASDF's own source registry. Take one of these routes.

Inside a Nix shell built from the flake, `CL_SOURCE_REGISTRY` is exported for
you and nothing further is needed:

```sh
nix develop
```

Outside Nix, point the registry at the directory holding the checkout and its
siblings before loading. Either export the variable, where the trailing `//`
means "search this tree recursively" and the trailing `:` means "then fall back
to the inherited configuration":

```sh
export CL_SOURCE_REGISTRY="/path/to/checkouts//:"
```

or register the tree from Lisp:

```lisp
(asdf:initialize-source-registry
 '(:source-registry
   (:tree "/path/to/checkouts/")
   :ignore-inherited-configuration))
```

Point either form at the *parent* of the checkouts, not at `cl-chip8` itself.
`cl-chip8` depends directly on the sibling `nerima-lisp` systems `cl-prolog-kit`,
`cl-tty-kit`, `cl-cli`, `cl-concurrent-kit`, `cl-date-kit`, and `cl-host-kit`
(plus SBCL's bundled `sb-posix`), and those systems have dependencies of their
own, so every one of them must be resolvable. The repository's own
`run-tests.lisp` registers exactly this tree, and skips doing so when
`CL_SOURCE_REGISTRY` is already set.

## Run a ROM from Lisp

```lisp
(asdf:load-system "cl-chip8")
(cl-chip8:run :rom-path #p"/path/to/rom.ch8")
```

`run` initializes the CPU, memory, display, fontset, ROM, and keypad before
entering the terminal loop. Every argument is a keyword; there is no positional
ROM parameter. It needs a live terminal, resets all global machine state on
entry -- so it is not re-entrant -- and returns a `chip8-app` rather than
signaling a mid-run failure, which is read back with `cl-chip8:chip8-app-error`.
See the [Terminal guide](guide/terminal.md) for keyboard, rendering, sound, and
command-line behavior.

## Next steps

- Learn the state model and execution boundary in [Core Concepts](guide/core-concepts.md).
- See keyboard, rendering, sound, and CLI behavior in the [Terminal guide](guide/terminal.md).
- Check fixed instruction behavior and platform limits in [Compatibility](reference/compatibility.md).
