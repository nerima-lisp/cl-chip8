;;;; tools/coverage.lisp -- force an instrumented compile before reporting.
(require :asdf)

(require :sb-cover)

(declaim (optimize (sb-cover:store-coverage-data 3)))

(defun script-directory ()
  (make-pathname
   :name
   nil
   :type
   nil
   :defaults
   (or
    *load-truename*
    *compile-file-truename*
    (error "Unable to determine the script location"))))

(defun project-root ()
  (truename (merge-pathnames #p"../" (script-directory))))

(defun local-source-directories (root)
  (let ((organization-root (truename (merge-pathnames #p"../" root))))
    (loop for name in (list
                       "cl-chip8"
                       "cl-prolog-kit"
                       "cl-tty-kit"
                       "cl-cli"
                       "cl-concurrent-kit"
                       "cl-boundary-kit"
                       "cl-date-kit"
                       "cl-host-kit"
                       "cl-codec-kit"
                       "cl-weave")
          for directory = (merge-pathnames
                           (format nil "~A/" name)
                           organization-root)
          when (probe-file directory)
            collect (truename directory))))

(defun configure-local-source-registry (root)
  (asdf:initialize-source-registry
   `(:source-registry
     ,@(mapcar (lambda (directory) `(:directory ,directory))
               (local-source-directories root))
     :ignore-inherited-configuration)))

(let ((root (project-root)))
  (configure-local-source-registry root))
(asdf:load-system "cl-host-kit")

(defun configure-isolated-output-cache (directory root)
  (let ((cache-root (merge-pathnames #p"asdf-cache/" directory))
        (source-roots (local-source-directories root)))
    (ensure-directories-exist cache-root)
    (asdf:initialize-output-translations
     `(:output-translations
       ,@(loop for source-root in source-roots
               for source-name = (car (last (pathname-directory source-root)))
               for cache = (merge-pathnames
                            (format nil "~A/" source-name)
                            cache-root)
               do (ensure-directories-exist cache)
               collect `(,(merge-pathnames #p"**/*.*" source-root)
                         (,cache :implementation)))
       :ignore-inherited-configuration))))

(defun coverage-directory (root)
  (let ((configured (host-kit:getenv "CL_CHIP8_COVERAGE_DIR")))
    (host-kit:ensure-directory-pathname
     (if configured
         (host-kit:ensure-pathname configured)
         (merge-pathnames #p"coverage/" root)))))

(defun coverage-excluded-source-files (root)
  "Source files deliberately left out of the coverage measurement.

Every entry below states the reason it is here, and the reason has to be one a
reader can check against the file. An unexplained exclusion is how this list
came to hide the emulator's own 35-instruction rulebase: OPCODES, CONDITIONS
and FONTSET were dropped from it because each has real branches and real tests
(t/opcodes-*-test.lisp, t/fontset-test.lisp, and the CONDITION assertions
throughout the suite), so measuring around them made the reported figure mean
nothing.

Do not add a name here to make a threshold pass. Excluding a file to reach a
minimum measures the exclusion list, not the code."
  (mapcar
   (lambda (name)
     (merge-pathnames (format nil "src/~A.lisp" name) root))
   (list
    ;; Real-terminal-only. The outer loop reads *STANDARD-INPUT* and drives
    ;; cl-tty-kit raw-mode I/O, which a headless test process cannot enter;
    ;; src/app.lisp:1-4 records that boundary as covered by real-TTY smoke
    ;; tests instead. The cost of this entry, stated so it is not forgotten:
    ;; the deterministic tick helpers in the same file, which
    ;; t/integration-test.lisp does exercise, go unmeasured along with it,
    ;; because sb-cover excludes whole files and not regions.
    "app"
    ;; Real-terminal-only, the same boundary as "app": %RUN-HANDLER opens a
    ;; terminal once the ROM has loaded, so only the pre-terminal failure
    ;; path is reachable from a test -- see the note at t/cli-test.lisp:3-5.
    "cli"
    ;; DEFPACKAGE and nothing else (src/package.lisp:17). A package
    ;; definition is a load-time form with no branch a test can take.
    "package"
    ;; DEFCONSTANT/DEFVAR declarations only (src/memory-types.lisp:6-14).
    "memory-types"
    ;; DEFVAR/DEFCONSTANT declarations only (src/state-types.lisp:6-20).
    "state-types"
    ;; DEFPARAMETER/DEFVAR declarations only (src/keypad-types.lisp:6-19).
    "keypad-types"
    ;; DEFCONSTANT/DEFVAR declarations plus the WITH-DISPLAY-LOCK macro
    ;; (src/display-types.lisp:4-33); the macro body runs at macroexpansion
    ;; time, so no test run can attribute it.
    "display-types"
    ;; DEFCONSTANT/DEFPARAMETER declarations only
    ;; (src/render-types.lisp:4-18).
    "render-types"
    ;; DEFSTRUCT and DEFCONSTANT declarations only
    ;; (src/concurrent-render-types.lisp:3-58).
    "concurrent-render-types"
    ;; A single DEFMACRO (src/concurrent-render-macros.lisp:4), expanded at
    ;; compile time; its call sites are measured in concurrent-render.lisp.
    "concurrent-render-macros")))

(defun coverage-report-pathnames (directory)
  (let ((index (merge-pathnames #p"cover-index.html" directory)))
    (unless (probe-file index)
      (error "Coverage index was not generated: ~A" index))
    (loop
      with html = (uiop:read-file-string index)
      with marker = "href='"
      with start = 0
      for marker-position = (search marker html :start2 start)
      while marker-position
      for href-start = (+ marker-position (length marker))
      for href-end = (position #\' html :start href-start)
      for relative = (and href-end (subseq html href-start href-end))
      do (setf start (if href-end href-end (length html)))
      when (and relative
                (not (string= relative "cover-index.html"))
                (string-equal (pathname-type (pathname relative)) "html"))
        collect (merge-pathnames relative directory))))

(defconstant +coverage-non-breaking-space+ (code-char 160)
  "SB-COVER emits every source-line indent as &#160;, so a decoded report line
is padded with NO-BREAK SPACE rather than #\\Space and the ordinary whitespace
bag does not trim it.")

(defun coverage-whitespace-p (character)
  (or (member character '(#\Space #\Tab #\Return #\Newline))
      (eql character +coverage-non-breaking-space+)))

(defun decode-coverage-entities (string)
  "Decode the &#NN; numeric character entities SB-COVER writes into its HTML.

Only the numeric form is handled, because that is the only form SB-COVER
emits: it escapes every non-alphanumeric byte as &#NN; rather than using the
named entities."
  (with-output-to-string (out)
    (let ((index 0)
          (length (length string)))
      (loop
        while (< index length)
        do (let ((character (char string index)))
             (if (and (char= character #\&)
                      (< (1+ index) length)
                      (char= (char string (1+ index)) #\#))
                 (let* ((semicolon (position #\; string :start index))
                        (code (and semicolon
                                   (parse-integer string
                                                  :start (+ index 2)
                                                  :end semicolon
                                                  :junk-allowed t))))
                   (cond
                     (code
                      (write-char (code-char code) out)
                      (setf index (1+ semicolon)))
                     (t
                      (write-char character out)
                      (incf index))))
                 (progn
                   (write-char character out)
                   (incf index))))))))

(defun strip-html-tags (string)
  (with-output-to-string (out)
    (let ((depth 0))
      (loop for character across string
            do (case character
                 (#\< (incf depth))
                 (#\> (when (plusp depth) (decf depth)))
                 (t (when (zerop depth) (write-char character out))))))))

(defun coverage-report-source-lines (html)
  "Every source line SB-COVER rendered, in file order, as (UNEXECUTED-P .
TEXT).

SB-COVER emits one <div class='source'> row per source line, each holding a
line-number cell and then the line's text split into <span class='state-N'>
runs. A line is unexecuted when any of its runs carries state-2. Parsing by
row rather than by span is what lets a span be attributed to the top-level
form it sits in -- see COVERAGE-LINE-TOPLEVEL-HEAD."
  (loop
    with marker = "<div class='source'>"
    with start = 0
    for position = (search marker html :start2 start)
    while position
    for row-end = (or (search "</nobr>" html :start2 position) (length html))
    for row = (subseq html position row-end)
    for number-end = (search "</div>" row)
    for content = (if number-end (subseq row (+ number-end 6)) row)
    do (setf start row-end)
    collect (cons (when (search "state-2" content) t)
                  (decode-coverage-entities (strip-html-tags content)))))

(defun coverage-line-toplevel-head (text)
  "When TEXT opens a top-level form, return its head and second token, both
downcased, as two values. Otherwise return NIL.

A top-level form is recognised by an open paren in column 0, which is what
every Lisp file in this tree uses and what `paredit inspect check` keeps true.
SB-COVER prefixes each rendered line with one &#160;, so column 0 is the
character after that single pad."
  (let* ((text (if (and (plusp (length text))
                        (eql (char text 0) +coverage-non-breaking-space+))
                   (subseq text 1)
                   text)))
    (when (and (plusp (length text)) (char= (char text 0) #\())
      (let* ((tokens (loop with index = 1
                           with length = (length text)
                           repeat 2
                           for token-start = (progn
                                               (loop while
                                                     (and (< index length)
                                                          (coverage-whitespace-p
                                                           (char text index)))
                                                     do (incf index))
                                               index)
                           for token-end = (progn
                                             (loop while
                                                   (and (< index length)
                                                        (not
                                                         (coverage-whitespace-p
                                                          (char text index)))
                                                        (not
                                                         (find (char text index)
                                                               "()")))
                                                   do (incf index))
                                             index)
                           collect (string-downcase
                                    (subseq text token-start token-end)))))
        (values (first tokens) (second tokens))))))

(defparameter *coverage-load-time-definition-heads*
  '("in-package" "defvar" "defparameter" "defconstant" "defmacro"
    "define-condition")
  "Heads of the top-level forms SB-COVER cannot credit.

Establishing why this list is not a way of hiding untested code: a probe that
performs the instrumented `asdf:load-system ... :force t` and then reads
CL-WEAVE::COVERAGE-STATISTICS with zero tests run reports 0 covered
expressions out of 1509, across every measured file. SB-COVER records nothing
for load-time execution. For a top-level definition form in a system that
loaded successfully, \"never executed\" is therefore not a state this tool can
tell apart from \"executed at load, uncredited\" -- the system could not have
loaded at all otherwise. Asserting such a form carries an execution mark
asserts something SB-COVER does not report.

DEFMACRO is here on the same footing, and it is worth spelling out because it
looks like the loosest entry: a macro body runs at its callers'
macroexpansion time, and SB-COVER credits none of it either. Every line of
DEFINE-CHIP8-CONDITION in src/conditions.lisp is marked unexecuted even
though it demonstrably expanded seven times -- the seven conditions it defines
exist and their reports format correctly.

Deliberately NOT here, though it was proposed: DEFINE-CHIP8-CONDITION. Its
regions ARE credited, because the :REPORT closure it generates runs at
runtime whenever a test formats the condition. Excluding it would have hidden
precisely the gap that t/opcodes-flow-test.lisp's printed-representation test
was added to close -- before that test, CHIP8-INVALID-OPCODE's whole region
was unexecuted; after it, no DEFINE-CHIP8-CONDITION region is. An entry here
must be a form SB-COVER cannot credit, never a form that merely happens to be
uncovered today.")

(defun coverage-load-time-definition-p (head second)
  "True when HEAD/SECOND name a top-level form SB-COVER cannot credit."
  (or (member head *coverage-load-time-definition-heads* :test #'string=)
      ;; The ordered opcode rulebase is one top-level (SETF *RULEBASE* ...)
      ;; whose body is quoted cl-prolog-kit clause DATA, not Lisp code paths, and
      ;; it is installed at load. Matched on the place as well as the head so
      ;; this never becomes a blanket exemption for SETF.
      (and (string= head "setf") (string= second "*rulebase*"))))

(defun unexecuted-coverage-bodies (pathname)
  "Unexecuted source lines in the report at PATHNAME that SB-COVER could have
credited and did not.

Each line is attributed to the top-level form enclosing it, and the line is
reported only when that form is one SB-COVER can credit. This matches the
form HEAD and never a bare token, so an unexecuted DEFUN body is still
reported: its enclosing head is DEFUN, which is not exempt. A line that opens
a form this parser cannot classify keeps the enclosing head it inherited, and
an unrecognised head is reported rather than skipped, so the gate fails
loudly instead of silently widening."
  (loop
    with head = nil
    with second = nil
    for (unexecuted-p . text) in (coverage-report-source-lines
                                  (uiop:read-file-string pathname))
    do (multiple-value-bind (line-head line-second)
           (coverage-line-toplevel-head text)
         (when line-head
           (setf head line-head
                 second line-second)))
    when (and unexecuted-p
              (not (coverage-load-time-definition-p head second)))
      collect (format nil "~A [in top-level (~A ~A ...)]"
                      (string-left-trim (list +coverage-non-breaking-space+)
                                        text)
                      (or head "?")
                      (or second ""))))

(defparameter *coverage-minimum-expression* 95
  "Expression-coverage percentage the run must reach. Bound once and used both
to gate the run and to print the summary, so the reported minimum cannot drift
away from the enforced one.

The measured subset stood at 95.63% (1443/1509 forms) when this threshold was
set, so 95 leaves roughly 0.63 points of headroom -- about nine expressions at
1/1509 = 0.066 points each. The margin exists so that one unrelated added
expression cannot turn CI red; it is deliberately under ten expressions so
that a real block of dead code still trips the gate rather than being absorbed.

The residual 66 uncovered expressions are top-level definition forms --
IN-PACKAGE in every measured file, plus the DEFVAR/DEFMACRO/DEFINE-CONDITION/
DEFCONSTANT/DEFPARAMETER forms and the (SETF *RULEBASE* ...) installation in
opcodes.lisp, conditions.lisp and fontset.lisp. SB-COVER does not credit them.
What establishes that, and what a future reader can re-run instead of
re-deriving it: a probe that performs the instrumented
`asdf:load-system \"cl-chip8/test\" :force t` and then reads
CL-WEAVE::COVERAGE-STATISTICS with ZERO tests run reports 0 covered
expressions out of 1509, and 0.0% for all fourteen measured files. Nothing
that runs at load time is counted, so no test can move these numbers.

Two things this comment deliberately does NOT claim. First, the MECHANISM is
not established: why SB-COVER credits nothing from the load is unknown. The
available conjecture -- that SB-COVER's marks live in the code component
compiled for each top-level form, which becomes garbage once the form has run
and so is not around to be counted -- is UNVERIFIED, and no measurement here
supports it. Do not repeat it as fact.

Second, a plausible explanation that was TESTED AND REFUTED, recorded so it is
not re-run: that CL-WEAVE's runner defaults :COVERAGE-RESET to T (see RUN-ALL
in cl-weave/src/runner-api.lisp) and zeroes SB-COVER's counters AFTER the load
has already executed every top-level form. Running the suite with
:COVERAGE-RESET NIL against an otherwise identical control arm with it left on
produces byte-identical totals -- 95.56% (1442/1509) on both, with identical
per-file numbers -- and the zero-tests probe above shows there is no load-time
coverage for a reset to erase in the first place. The reset is not the cause.")

(defparameter *coverage-minimum-branch* 100
  "Branch-coverage percentage the run must reach. See
*COVERAGE-MINIMUM-EXPRESSION*.")

(defun coverage-source-manifest ()
  "Every production source file ASDF itself lists for the cl-chip8 system.

Derived from the component list rather than from a second hand-maintained
list, so a component added to cl-chip8.asd appears in the denominator on the
commit that adds it instead of being silently absent from the measurement."
  (loop for component in (asdf:component-children (asdf:find-system "cl-chip8"))
        for pathname = (asdf:component-pathname component)
        when (probe-file pathname)
          collect (truename pathname)))

(defun normalized-namestrings (pathnames)
  (loop for pathname in pathnames
        for resolved = (probe-file pathname)
        when resolved
          collect (namestring (truename resolved))))

(defun coverage-statistics (include-pathnames exclude-pathnames)
  (let ((statistics (find-symbol "COVERAGE-STATISTICS" "CL-WEAVE")))
    (unless (and statistics (fboundp statistics))
      (error "CL-WEAVE::COVERAGE-STATISTICS is unavailable; cannot report ~
              measured coverage."))
    (funcall statistics
             :include-pathnames include-pathnames
             :exclude-pathnames exclude-pathnames)))

(defun coverage-percentage (covered total)
  (if (zerop total)
      0.0
      (/ (* 100.0 covered) total)))

(defun report-coverage-summary (include-pathnames excluded-source-files)
  "Print what was actually measured, over how many files, against how many the
system declares. Printed on both the passing and the failing path, so a run
that trips a threshold still says what it measured."
  (let* ((manifest (normalized-namestrings (coverage-source-manifest)))
         (excluded (normalized-namestrings excluded-source-files))
         (measured (set-difference manifest excluded :test #'string=))
         (stale (set-difference excluded manifest :test #'string=))
         (statistics (coverage-statistics include-pathnames
                                          excluded-source-files)))
    (format t
            "~&Coverage scope: ~D of ~D source files declared by cl-chip8.asd ~
             were measured; ~D excluded (see COVERAGE-EXCLUDED-SOURCE-FILES ~
             in this file for each exclusion's reason).~%~
             The percentages below describe that measured subset ONLY. They ~
             are not whole-tree coverage.~%"
            (length measured)
            (length manifest)
            (length excluded))
    (dolist (pathname stale)
      (format *error-output*
              "~&Stale coverage exclusion: ~A is excluded but is not a ~
               cl-chip8.asd component.~%"
              pathname))
    (destructuring-bind (&key expression-covered expression-total
                              branch-covered branch-total)
        statistics
      (format t
              "~&Expression coverage (measured subset): ~,2F% ~
               (~D/~D forms; minimum ~D%).~%~
               Branch coverage (measured subset): ~,2F% ~
               (~D/~D branches; minimum ~D%).~%"
              (coverage-percentage expression-covered expression-total)
              expression-covered
              expression-total
              *coverage-minimum-expression*
              (coverage-percentage branch-covered branch-total)
              branch-covered
              branch-total
              *coverage-minimum-branch*))
    statistics))

(defun assert-executable-coverage (directory)
  (let ((reports (coverage-report-pathnames directory)))
    (unless reports
      (error "Coverage index contains no source reports: ~A"
             (merge-pathnames #p"cover-index.html" directory)))
    (let ((gaps (loop for report in reports
                      append (mapcar (lambda (body)
                                       (list report body))
                                     (unexecuted-coverage-bodies report)))))
      (when gaps
        (dolist (gap gaps)
          (format *error-output*
                  "~&Unexecuted executable coverage span in ~A: ~A~%"
                  (first gap)
                  (second gap)))
        (error "Executable coverage gate failed.")))
    (format t
            "~&No unexecuted executable span in ~D measured source report~:P ~
             (top-level definition forms SB-COVER cannot credit excluded: ~
             ~{~A~^, ~}, and the (SETF *RULEBASE* ...) installation -- see ~
             *COVERAGE-LOAD-TIME-DEFINITION-HEADS* for why each is out of ~
             reach). This covers the measured subset reported above, not the ~
             whole source tree.~%"
            (length reports)
            *coverage-load-time-definition-heads*)))

(let* ((root (project-root))
       (directory (coverage-directory root))
       (source-directory (merge-pathnames #p"src/" root))
       (excluded-source-files (coverage-excluded-source-files root)))
  (configure-local-source-registry root)
  (ensure-directories-exist directory)
  (configure-isolated-output-cache directory root)
  (format t "~&Forcing instrumented compilation...~%")
  (asdf:load-system "cl-chip8/test" :force t)
  (let ((runner (find-symbol "RUN-TESTS" "CL-CHIP8/TEST")))
    (unless (and runner (fboundp runner))
      (error "CL-CHIP8/TEST:RUN-TESTS is unavailable"))
    ;; The summary runs in the cleanup so a run that trips a threshold still
    ;; reports the numbers it measured instead of dying silently on them. A
    ;; failure inside the summary itself must not replace the primary error,
    ;; hence the handler-case.
    ;;
    ;; Before adding a coverage keyword below, read RUN-TESTS in t/package.lisp:
    ;; its lambda list is fixed and forwards a hardcoded :COVERAGE-RESET T, so
    ;; it accepts only the seven :COVERAGE-* keywords already passed here. An
    ;; unrecognised one signals UNKNOWN-KEYWORD-ARGUMENT, which aborts before
    ;; any test runs -- and because the summary above still executes from the
    ;; cleanup, the run ends by printing "0.00% (0/1509 forms)". That reads
    ;; like a catastrophic collapse in coverage and is nothing of the kind.
    ;; A 0/N summary from this tool means the harness failed, not that
    ;; coverage vanished; check for a keyword error above it before believing
    ;; the number. To vary an option RUN-TESTS does not expose, call
    ;; CL-WEAVE:RUN-ALL directly from a throwaway copy of this script rather
    ;; than widening the wrapper.
    (unwind-protect
         (funcall runner
                  :coverage t
                  :coverage-output (merge-pathnames #p"cl-chip8.coverage"
                                                    directory)
                  :coverage-report-directory directory
                  :coverage-include-pathnames (list source-directory)
                  :coverage-exclude-pathnames excluded-source-files
                  :coverage-minimum-expression *coverage-minimum-expression*
                  :coverage-minimum-branch *coverage-minimum-branch*)
      (handler-case
          (report-coverage-summary (list source-directory)
                                   excluded-source-files)
        (error (condition)
          (format *error-output*
                  "~&Could not report the measured coverage summary: ~A~%"
                  condition)))))
  (assert-executable-coverage directory)
  (format t "~&Coverage report: ~A~%"
          (merge-pathnames #p"cover-index.html" directory))
  (host-kit:quit 0))
