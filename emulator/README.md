# emulator/ — xnu-qemu-arm64, for phase1 tweak-logic testing only

**Scope note:** this exists solely to test [phase1](../phase1/)'s SpringBoard-hook
tweak logic (owner-lock overlay now; duress PIN / Safe Mode / hidden control
hub later) without the real iPhone 6, which is currently Activation
Locked/presumed wiped — see the root `README.md`'s "Current blocker" section
and `phase3/README.md`'s ramdisk incident writeup. **This has no bearing on
phase2 or phase3** — those depend on real SecureROM/checkm8 bootrom
exploitation and DFU hardware; there is no emulator equivalent for that
layer, and nothing here should be read as progress on it.

Also: **the device this project actually targets is the iPhone 6 (A8,
s8000, iOS 12.5.8)**. xnu-qemu-arm64 only supports the **iPhone 6s Plus
(A9, s8003/n66/t8015-class SoC, iOS 12.1)** — a different chip and a
different iOS build. Anything verified here is evidence the *tweak's
SpringBoard-hook logic in general* works, not a substitute for real
iPhone-6-specific verification.

## What's real and verified so far (2026-09-08)

- **Host has KVM**: `/dev/kvm` present, `vmx` CPU flag present, `kvm_intel`
  module loaded. Hardware-accelerated QEMU is viable here, not just slow
  TCG software emulation.
- **No passwordless sudo on this box** (same limitation noted elsewhere in
  this project's history) — worked around it for the QEMU build
  dependencies (`libglib2.0-dev`/`libgio-2.0-dev`, `libpixman-1-dev`,
  `libslirp-dev`, and their transitive deps) using `apt-get download`
  (doesn't need root) + `dpkg-deb -x` (extracts a `.deb`'s contents into an
  arbitrary directory, also doesn't need root) into a local prefix at
  `~/emulator-deps/prefix`, with `PKG_CONFIG_PATH`/`PKG_CONFIG_SYSROOT_DIR`/
  `C_INCLUDE_PATH`/`LIBRARY_PATH`/`LD_LIBRARY_PATH` pointed at it (see
  `~/.bashrc.emulator-env`, `source` it before building). **Verified
  working**: compiled and ran a real C program linking `glib-2.0`,
  `pixman-1`, and `slirp` through this prefix with no root at any point.
  `ninja`/`meson` were installed via `pip3 install --user`, also no root
  needed.
- **Cloned two repos** (both gitignored here, not vendored into this repo
  — see `.gitignore`):
  - `xnu-qemu-arm64/` — the gitlab.com/osx-hackintosh-and-old-macs-support
    fork of alephsecurity's original (chosen for apparently more recent
    activity; its actual `README.md` content turned out to be identical to
    upstream's, so treat it as equivalent to
    github.com/alephsecurity/xnu-qemu-arm64, not as further-advanced work
    — that "recent activity" signal from earlier web research did not pan
    out under closer inspection here).
  - `xnu-qemu-arm64-tools/` — the ASN1/kernelcache/device-tree/ramdisk
    decode scripts and the custom block-device driver
    (`aleph_bdev_drv`) the main project needs.
  - `docs/upstream-build-tutorial.md` — a local copy of the project's own
    wiki build tutorial (fetched via `git clone
    github.com/alephsecurity/xnu-qemu-arm64.wiki.git`, since the rendered
    wiki page itself doesn't serve readable content without JS execution).

## The concrete blocker: disk-image prep is macOS-only

Read `docs/upstream-build-tutorial.md` in full before continuing this. The
kernel/device-tree extraction steps (ASN1 decode, LZSS decompress) are
plain Python and Linux-portable — no issue there. **The disk-image
preparation stage is not.** It requires, in this order, on the *decoded
ramdisk* as a real HFS+ volume:

- `hdiutil resize`/`hdiutil attach`/`hdiutil detach` — macOS-only, no
  direct Linux equivalent for this exact resize-then-mount-as-writable
  workflow.
- `sudo rsync` + `sudo chown root ...dyld_shared_cache_arm64` on the
  *mounted* volume — needs real HFS+ read-write mount with working Unix
  ownership semantics.
- Patching and re-signing `/sbin/launchd` in place on the mounted volume
  (a single hardcoded instruction patch via Ghidra, `jtool --sign`).
- Copying `rootlessJB`'s `iosbinpack64` (~bash, dropbear, mount, etc.) onto
  the volume, adding four `LaunchDaemon` plists.

None of that has a documented Linux path in this project. This is the same
category of problem phase3's own ramdisk work already ran into once
("HFS+ *write* support on Linux is meaningfully less mature than read
support") — except here we additionally need in-place patching and
re-signing of a binary on the mounted volume, which is more than phase3
ever attempted.

**Not attempted here, and why:** going further would mean standing up a
real Linux-native HFS+ read-write path (candidates worth checking, not
verified: the `hfsplus` kernel driver's native RW mount support for
non-journaled volumes via `mount -t hfsplus -o rw` — this may just work
and hasn't been tried; `hfsprogs` for `mkfs.hfsplus`/`fsck.hfsplus`;
`libhfsp0`/`libhfsp-dev` as a userspace alternative), plus a Linux-capable
binary patcher/signer in place of Ghidra+jtool's macOS workflow (`jtool2`
does have a documented Linux build per newosxbook.com, not verified here).
That's a real, separate side-investigation, not a quick unblock — stopping
here rather than open-ending into it, per this task's own scope.

## Update 2026-09-08: step 1 below is confirmed working

Verified directly on this box, no IPSW needed for the test: `mkfs.hfsplus`
(already installed, `/usr/sbin/mkfs.hfsplus`) made a small **non-journaled**
test volume as a normal user; `sudo mount -t hfsplus -o
rw,loop,uid=$(id -u),gid=$(id -g) test.hfs mnt/` mounted it read-write
(the `uid=`/`gid=` options are needed or the mounted root defaults to
root-owned); a file written through the mount was confirmed to actually
persist to the underlying image (`fsck.hfsplus -n` reported the volume
clean afterward, and the written bytes are present via `strings` directly
on the image file, not just page-cache). So the Linux `hfsplus` driver's
RW mount is real and sufficient **for a non-journaled volume** — the
open question is now specifically whether the real ramdisk from the
target IPSW is journaled or not (restore ramdisks are typically not, but
unverified for this exact device/build).

Command sequence that worked (adapt paths for the real decoded ramdisk):

```
sudo mount -t hfsplus -o rw,loop,uid=$(id -u),gid=$(id -g) <image> <mountpoint>
# ... cp/rsync/patch as the tutorial's hdiutil-mounted steps describe ...
sudo umount <mountpoint>
```

## If this is picked up again

1. ~~Try `sudo mount -t hfsplus -o rw,loop hfs.main /mnt/somewhere`~~ —
   **done, confirmed working for non-journaled volumes, see above.**
2. Download the target IPSW, run the tutorial's (Linux-portable) Python
   kernel/device-tree/ramdisk decode steps to get the real
   `048-32651-104.dmg.out`-style HFS+ image, and check whether it's
   journaled (`fsck.hfsplus -n` will say). If journaled, RW mount may
   still fail — that's the next real unknown, untested here.
3. `jtool2`'s Linux build needs verifying for the two ad-hoc-signing steps
   (`/bin/tunnel`, patched `launchd`).
4. Everything from "clone xnu-qemu-arm64" and "configure/make" onward in
   `docs/upstream-build-tutorial.md` is Linux-native and just needs
   `source ~/.bashrc.emulator-env` first for the dependency prefix.
