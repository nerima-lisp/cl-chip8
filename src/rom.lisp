;;;; src/rom.lisp -- reading a ROM file from disk into *MEMORY*.
(in-package #:cl-chip8)

(defun regular-file-p (path)
  "True when PATH exists (PROBE-FILE succeeds) and SB-POSIX:STAT reports it as
a regular file. False for a directory or a non-regular special file (a FIFO,
a character/block device, a socket); also false when PROBE-FILE cannot
resolve PATH at all -- see CHECK-REGULAR-ROM-FILE below for why that case is
left to the caller's own OPEN rather than folded into this predicate."
  (and (probe-file path)
       (sb-posix:s-isreg (sb-posix:stat-mode (sb-posix:stat (namestring path))))))

(defun check-regular-rom-file (path)
  "Signal CHIP8-ROM-NOT-REGULAR-FILE when PATH resolves but is not a regular
file. FILE-LENGTH/READ-SEQUENCE on a FIFO or character device (e.g.
/dev/zero) can return an unreliable length or block indefinitely, so this
runs before LOAD-ROM-FILE! ever opens PATH for reading. A PATH that PROBE-
FILE cannot resolve is left alone here -- READ-FILE-BYTES' own OPEN raises
the ordinary, more specific FILE-ERROR for a plain missing-file case.

SB-POSIX is used directly rather than adding cl-host-kit (which has an
equivalent FILE-METADATA-KIND predicate) as a new formal dependency:
CODING_STANDARD.md's SBCL-only stance already treats sb-posix as free (SBCL-
bundled, counted as neither an external nor an org-internal dependency), and
neither cl-tty-kit nor cl-cli -- cl-chip8's existing dependencies -- expose a
file-kind predicate of their own that would cover this without one."
  (when (and (probe-file path) (not (regular-file-p path)))
    (error 'chip8-rom-not-regular-file :path path))
  (values))

(defun read-file-bytes (path &key max-size)
  "Return the contents of the file at PATH as a fresh (UNSIGNED-BYTE 8)
vector. When MAX-SIZE is given, PATH's length is checked against it (via
FILE-LENGTH, before any byte array is allocated or any byte read) and
CHIP8-ROM-TOO-LARGE is signaled immediately if it is exceeded -- this is a
local CLI tool, so a user accidentally pointing it at an arbitrarily large
file must not have the whole thing read into memory before being told no."
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((size (file-length stream)))
      (when (and max-size (> size max-size))
        (error 'chip8-rom-too-large :size size :available max-size))
      (let ((bytes (make-array size :element-type '(unsigned-byte 8))))
        (read-sequence bytes stream)
        bytes))))

(defun load-rom-file! (path)
  "Read the ROM file at PATH and load it into *MEMORY* at +ROM-LOAD-ADDRESS+
via stage 1's LOAD-BYTES-INTO-MEMORY. CHECK-REGULAR-ROM-FILE runs first, so a
FIFO or device path is rejected before any read is attempted; READ-FILE-
BYTES is then given the same budget LOAD-BYTES-INTO-MEMORY itself enforces
(+MEMORY-SIZE+ - +ROM-LOAD-ADDRESS+, 3584 bytes), so an oversized file is
rejected via CHIP8-ROM-TOO-LARGE before its bytes are ever read into memory,
not after -- LOAD-BYTES-INTO-MEMORY's own check remains as defense in depth
for any other caller of it. Returns the byte vector."
  (check-regular-rom-file path)
  (load-bytes-into-memory
   (read-file-bytes path :max-size (- +memory-size+ +rom-load-address+))
   +rom-load-address+))
