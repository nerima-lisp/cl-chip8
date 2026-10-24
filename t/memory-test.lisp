(in-package #:cl-chip8/test)
(describe "machine memory"
  (it-each ((:cosmac-vip 4096 (:lores) (:chip8) 15)
            (:modern 4096 (:lores) (:chip8) 12)
            (:schip 4096 (:lores :hires) (:chip8 :schip-large) 30)
            (:schip-legacy 4096 (:lores :hires) (:chip8 :schip-large) 30)
            (:xo-chip 65536 (:lores :hires) (:chip8 :schip-large) 100))
    "resolves the ~A platform profile"
    (name capacity resolutions font-sets tickrate)
    (let ((profile (find-chip8-platform name))
          (string-profile
            (find-chip8-platform (string-downcase (symbol-name name)))))
      (expect (chip8-platform-name profile) :to-be name)
      (expect (chip8-platform-name string-profile) :to-be name)
      (expect (chip8-platform-memory-size profile) :to-be capacity)
      (expect (chip8-platform-default-tickrate profile) :to-be tickrate)
      (expect (equal (chip8-platform-resolutions profile) resolutions)
              :to-be-truthy)
      (expect (equal (chip8-platform-font-sets profile) font-sets)
              :to-be-truthy)))
  (it "allocates the selected machine capacity"
    (let ((modern (make-chip8-machine))
          (xo-chip (make-chip8-machine :platform :xo-chip))
          (modern-with-64k-override
            (make-chip8-machine :platform :modern :memory-size 65536)))
      (expect (chip8-machine-memory-size modern) :to-be 4096)
      (expect (chip8-machine-memory-size xo-chip) :to-be 65536)
      (expect (chip8-platform-name (chip8-machine-platform modern-with-64k-override))
              :to-be :modern)
      (expect (chip8-machine-memory-size modern-with-64k-override) :to-be 65536)))
  (it "checks access against each machine's memory boundary"
    (let ((modern (make-chip8-machine))
          (xo-chip (make-chip8-machine :platform :xo-chip))
          (modern-with-64k-override
            (make-chip8-machine :platform :modern :memory-size 65536)))
      (expect (check-memory-access modern 4095 1) :to-be t)
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access modern 4095 2))
      (check-memory-access xo-chip 65535 1)
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access xo-chip 65535 2))
      (check-memory-access modern-with-64k-override 65535 1)
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access modern-with-64k-override 65535 2))))
  (it "reads and writes bytes"
    (let ((m (make-chip8-machine)))
      (setf (memory-read m 100) 42)
      (expect (memory-read m 100) :to-be 42)))
  (it "resets memory and accepts empty byte loads"
    (let ((m (make-chip8-machine)))
      (setf (memory-read m #x50) 0
            (memory-read m #x300) #xa5)
      (memory-reset! m)
      (expect (memory-read m #x50) :to-be #xf0)
      (expect (memory-read m #x300) :to-be 0)
      (setf (memory-read m #x300) #x5a)
      (load-bytes-into-memory m #() #x300)
      (expect (memory-read m #x300) :to-be #x5a)))
  (it "checks the default 4K range before access"
    (let ((m (make-chip8-machine)))
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access m 4095 2))))
  (it "rejects invalid memory bounds and accepts an empty load at capacity"
    (let ((m (make-chip8-machine)))
      (expect (check-memory-access m 4096 0) :to-be t)
      (load-bytes-into-memory m #() 4096)
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access m -1 1))
      (signals chip8-memory-access-out-of-bounds
        (check-memory-access m 0 -1))
      (signals chip8-memory-access-out-of-bounds
        (load-bytes-into-memory m #() -1))
      (signals chip8-memory-access-out-of-bounds
        (load-bytes-into-memory m #() 4097))
      (signals chip8-rom-too-large
        (load-bytes-into-memory m #(1) 4096))))
  (it "accepts platform objects and string names and rejects unknown profiles"
    (let* ((profile (find-chip8-platform :modern))
           (profile-machine (make-chip8-machine :platform profile))
           (string-machine (make-chip8-machine :platform "modern")))
      (expect (eq (chip8-machine-platform profile-machine) profile)
              :to-be-truthy)
      (expect (chip8-machine-memory-size string-machine) :to-be 4096)
      (signals error (make-chip8-machine :platform :unknown))
      (signals error (make-chip8-machine :platform "unknown"))
      (signals type-error (make-chip8-machine :memory-size 8192)))))
