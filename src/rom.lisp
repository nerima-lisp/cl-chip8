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

This is an early rejection, NOT a guarantee about the object eventually
read. The check resolves PATH by name -- PROBE-FILE, then STAT, then
READ-FILE-BYTES' own OPEN, four separate resolutions -- so anyone who can
write to the containing directory can replace a regular file with a FIFO in
between, and the subsequent OPEN/FILE-LENGTH then blocks on it. Closing that
window means holding the object rather than the name: open once with
SB-POSIX:OPEN, FSTAT the descriptor, test S-ISREG against THAT, and only
then wrap the descriptor in a stream. Deliberately not done here, because
the obvious O_NOFOLLOW spelling would also reject a symlink to a perfectly
good ROM, which is a behavior change this release has not evaluated. The
practical exposure is a local user racing a directory they can already
write; it is a real defect, and it is stated here rather than implied away.

SB-POSIX is used directly rather than adding cl-host-kit (which has an
equivalent FILE-METADATA-KIND predicate) as a new formal dependency:
CODING_STANDARD.md's SBCL-only stance already treats sb-posix as free (SBCL-
bundled, counted as neither an external nor an org-internal dependency), and
neither cl-tty-kit nor cl-cli -- cl-chip8's existing dependencies -- expose a
file-kind predicate of their own that would cover this without one."
  (when (and (probe-file path) (not (regular-file-p path)))
    (error 'chip8-rom-not-regular-file :path path))
  (values))

(defun %read-file-bytes-from-stream (stream size)
  "Read SIZE bytes from STREAM into a fresh unsigned-byte vector.

READ-SEQUENCE is allowed to return before the requested end position, so a
single call is not enough to establish that a file was read completely. Keep
reading after a short read and signal CHIP8-ROM-SHORT-READ if EOF arrives
before SIZE bytes are available."
  (let ((bytes (make-array size :element-type '(unsigned-byte 8))))
    (loop with position = 0
          while (< position size)
          for next-position = (read-sequence bytes stream :start position)
          do (if (<= next-position position)
                 (error 'chip8-rom-short-read
                        :actual-size position
                        :expected-size size)
                 (setf position next-position)))
    bytes))

(defun read-file-bytes (path &key max-size)
  "Return the contents of the file at PATH as a fresh (UNSIGNED-BYTE 8)
vector. When MAX-SIZE is given, PATH's length is checked against it (via
FILE-LENGTH, before any byte array is allocated or any byte read) and
CHIP8-ROM-TOO-LARGE is signaled immediately if it is exceeded -- this is a
local CLI tool, so a user accidentally pointing it at an arbitrarily large
file must not have the whole thing read into memory before being told no.

Also signals CHIP8-ROM-SHORT-READ, from %READ-FILE-BYTES-FROM-STREAM, when
the stream reaches EOF before FILE-LENGTH's byte count has been read."
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((size (file-length stream)))
      (when (and max-size (> size max-size))
        (error 'chip8-rom-too-large :size size :available max-size))
      (%read-file-bytes-from-stream stream size))))

(defun load-rom-file! (path)
  "Read the ROM file at PATH and load it into *MEMORY* at +ROM-LOAD-ADDRESS+
via LOAD-BYTES-INTO-MEMORY. CHECK-REGULAR-ROM-FILE runs first, so a
FIFO or device path is rejected before any read is attempted; READ-FILE-
BYTES is then given the same budget LOAD-BYTES-INTO-MEMORY itself enforces
(+MEMORY-SIZE+ - +ROM-LOAD-ADDRESS+, 3584 bytes), so an oversized file is
rejected via CHIP8-ROM-TOO-LARGE before its bytes are ever read into memory,
not after -- LOAD-BYTES-INTO-MEMORY's own check remains as defense in depth
for any other caller of it. Returns the byte vector.

Signals CHIP8-ROM-NOT-REGULAR-FILE for a resolvable non-regular path, and
propagates CHIP8-ROM-TOO-LARGE and CHIP8-ROM-SHORT-READ from READ-FILE-BYTES.
A path that does not resolve at all raises the ordinary FILE-ERROR from the
eventual OPEN."
  (check-regular-rom-file path)
  (load-bytes-into-memory
   (read-file-bytes path :max-size (- +memory-size+ +rom-load-address+))
   +rom-load-address+))
