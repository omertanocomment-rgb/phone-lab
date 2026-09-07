# Phase 3 — persistent userspace/OS work

Per the root `PLAN.md`, phase3 is the "genuine custom OS" tier, scoped into
three options "roughly in order of realism." This directory currently holds
the first and most realistic one: **LaunchDaemon persistence**, extending
phase1's jailbreak/tweak layer so OMERTA components can run independent of
SpringBoard, starting automatically post-jailbreak.

```
phase3/
├── userspace/
│   └── omerta-persistd/    built: minimal LaunchDaemon proof-of-concept
├── ramdisk/                stub — patched-ramdisk-via-Pongo option, not started
├── kernel/                 stub — not started
└── rootfs/                 stub — not started
```

## `userspace/omerta-persistd/`

A minimal LaunchDaemon (`com.omerta.iosui.daemon`, `/usr/libexec/omerta_persistd`),
built and tested on real hardware. It reuses `OwnerLock.m`/`.h` directly from
`../../phase1/OMERTAiOS-tweak/` (the same tested, Keychain-backed PIN storage
the tweak uses) rather than duplicating logic — this is a first real building
block toward a background "hidden control hub" process (phase1's own roadmap
item 4), not that feature itself.

What it does, in full: runs once at `launchd` load (`RunAtLoad`), calls
`[OMOwnerLock hasOwnerPin]`, appends one timestamped line to
`/var/mobile/omerta_persistd.log`, exits. No polling loop, no `KeepAlive`, no
network, no control-hub UI.

**A real packaging bug found and fixed during testing:** `launchd` refuses to
load a LaunchDaemon plist that's group/world-writable ("bad
ownership/permissions"), and Theos's `after-install:: install.exec "..."`
directive is *not* embedded into the `.deb` as an actual maintainer script —
it only runs during Theos's own `make install` (a direct SSH push during
dev), not on a plain `dpkg -i`. The fix was a real `layout/DEBIAN/postinst`
script (the actual dpkg convention Theos's `deb.mk`/`dm.pl` expect — verified
by reading `theos/makefiles/package/deb.mk` and `theos/vendor/dm.pl/dm.pl`
directly, not guessed), which `chmod`s/`chown`s the plist and loads it.
Confirmed end-to-end with a real clean install (remove, delete log,
reinstall) producing a fresh log line with no manual intervention.

**What's confirmed:** the daemon installs, self-corrects LaunchDaemon
permissions, loads via `launchd`, and successfully calls real `OwnerLock`
code — all verified live on the same real iPhone 6 phase1/phase2 testing
used, via `dpkg -i` over SSH and reading the resulting log.

**What's inferred, not separately re-tested tonight:** that it also
auto-loads on a genuine full device reboot. This follows directly from
`RunAtLoad`'s standard, well-documented launchd semantics (every
`/Library/LaunchDaemons/*.plist` loads on every boot — this is how *all*
LaunchDaemons work, not something specific to OMERTA's code), so it wasn't
re-verified with an actual DFU+rejailbreak cycle the way the genuinely novel
phase2 USB/framebuffer-console findings were. Worth a real reboot test
before leaning on this claim for anything security-sensitive.

## Not started

- Patched ramdisk via the phase2 Pongo module (`ramdisk/`) — upstream's
  `scripts/boot-checkra1n.py` shows the pattern (`modload` → `ramdisk` →
  `bootx`).
- Alternate kernel/rootfs boot (`kernel/`, `rootfs/`) — explicitly scoped in
  `PLAN.md` as a multi-month research project on its own, out of scope for
  now.
