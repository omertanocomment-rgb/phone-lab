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
├── ramdisk/                in progress — patched-ramdisk-via-Pongo option
│   └── tools/fetch_ramdisk.py   sources + unwraps a RestoreRamDisk from a real IPSW
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

## `ramdisk/` — patched ramdisk via the phase2 Pongo module

Upstream's `scripts/boot-checkra1n.py` shows the pattern: `modload` a KPF
module (this project already has one, built and verified —
`output/checkra1n-kpf-pongo` from the phase2 CI run), then push a raw
ramdisk image via the `ramdisk` shell command, set `kpf_flags 1`, then
`bootx` with `rootdev=md0` so XNU boots from the pushed ramdisk instead of
the real NAND rootfs — a "custom recovery-style environment, without
touching the installed iOS at all," per `PLAN.md`'s own framing.

**Sourced and verified so far, real hardware / real Apple data, nothing
invented:**

1. Found the exact-match IPSW for this project's own iPhone 6 —
   `iPhone_4.7_12.5.8_16H88_Restore.ipsw`, confirmed via
   `api.ipsw.me`'s public index and cross-checked against this specific
   phone's own `ideviceinfo` (`BuildVersion: 16H88`) and SHA1
   (`316fc685e887f3dd41fa620f12ecd4ae1e0bdc35`, matches exactly).
2. `BuildManifest.plist` inside the IPSW names the `n61ap` (iPhone 6)
   "Customer Erase Install" `RestoreRamDisk` as `038-87170-068.dmg`
   (91.7 MB) — extracted via `phase3/ramdisk/tools/fetch_ramdisk.py`
   (uses Python's `zipfile`, works against a local IPSW or, via a
   range-request-backed file-like object, a remote one without
   downloading the full ~3 GB archive).
3. That `.dmg` turned out to be an **IM4P** (IMG4 payload) container
   (`fourcc: rdsk`), not a raw disk image — confirmed and unwrapped with
   `pyimg4` (`pip3 install pyimg4`). **Turned out to be unencrypted**
   (`payload.encrypted == False`, checked, not assumed) — no device keys
   or published firmware keys needed at all for this specific
   IPSW/device/variant. Unwrapping gives a genuine, directly-readable
   Apple HFS+ filesystem image (confirmed via `file`:
   `Apple HFS Plus Extended ... data (mounted)`).
4. Browsed with `7z l`/`7z x` (its HFS+ plugin reads this directly, no
   mount/root needed) — a real Apple restore environment:
   `bin/`, `sbin/`, `usr/`, `System/Library/{CoreServices,LaunchDaemons,
   Frameworks,PrivateFrameworks}/`, `mnt1`-`mnt7` (restore-time mount
   points), etc.
5. **Identified the actual boot entry point to patch:**
   `System/Library/LaunchDaemons/com.apple.restored_external.plist` —
   `Label: com.apple.restored_external`, `RunAtLoad: true`,
   `ProgramArguments: /usr/local/bin/restored_external`. This is what
   actually runs at ramdisk boot and speaks Apple's real restore
   protocol over USB. The classic "SSH ramdisk" jailbreak pattern (and
   this project's own equivalent) is replacing this binary/plist so it
   launches something OMERTA-controlled instead — a shell, an SSH
   daemon, or eventually a custom status/control binary — rather than
   Apple's real restore handler.

**Not done yet, deliberately, per an explicit scope decision this
session:**

- Actually patching `restored_external` (or its plist) to launch
  something custom.
- **Repacking** the modified filesystem back into a valid raw HFS+
  image pongoOS's `ramdisk` command will accept. HFS+ *write* support on
  Linux is meaningfully less mature than read support (`7z` here was
  read-only) — this is a real unknown, not a solved problem, and is the
  next concrete blocker.
- Testing the full chain live (`checkra1n -k` → `modload` KPF →
  `ramdisk` → `bootx`) against the real phone.

**Not committed to git:** the ~92 MB ramdisk image itself (both wrapped
and unwrapped forms) — same reasoning as `phase2/pongo-src/` not being
vendored. Re-derive it with `tools/fetch_ramdisk.py` against a
sha1-verified IPSW rather than committing a large binary.

## `kernel/`, `rootfs/` — alternate kernel/rootfs boot

Not started. Explicitly scoped in `PLAN.md` as a multi-month research
project on its own, out of scope for casual continuation.
