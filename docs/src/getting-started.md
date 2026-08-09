# Getting Started

cl-chip8 runs CHIP-8 ROMs in a terminal. It supports SBCL and is packaged as a
Nix flake.

## Add the flake input

From a consuming flake, point at the released tag:

```nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.1.0";
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

## Run a ROM

```lisp
(asdf:load-system "cl-chip8")
(cl-chip8:run :rom-path #p"/path/to/rom.ch8")
```

`run` initializes memory, the CPU, display, fontset, ROM, and keypad before
entering the terminal loop. See the [Terminal guide](guide/terminal.md) for
keyboard, rendering, sound, and command-line behavior.

## Next steps

- Learn the state model and execution boundary in [Core Concepts](guide/core-concepts.md).
- See keyboard, rendering, sound, and CLI behavior in the [Terminal guide](guide/terminal.md).
- Check fixed instruction behavior and platform limits in [Compatibility](reference/compatibility.md).
