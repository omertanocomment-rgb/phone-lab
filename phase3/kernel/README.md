# phase3/kernel/ — genuine custom OS: mainline Linux on the real iPhone 6

**Scope:** this is `PLAN.md`'s "kernel/rootfs" tier — the "genuine custom OS"
option, explicitly called a multi-month research project. Started
2026-09-08 at the user's explicit request (not the smaller console-only
milestone). This is a *different, safer* mechanism than `phase3/ramdisk/`'s
abandoned approach: instead of hijacking Apple's own Customer-Erase-Install
restore ramdisk (which erased the test device), this loads a genuinely
independent, non-Apple Linux kernel + device tree over pongoOS's USB
protocol — no Apple restore/erase logic is ever invoked, and per every
source consulted (see below), **nothing in this boot path writes to the
device's internal NAND**. It's also independent of the device's current
Activation Lock state: DFU/pongoOS access operates entirely below
iOS/XNU/Apple's activation servers, so the real device's current Activation
Lock (see root `README.md`) does not block this work, only real-iOS testing.

Real, verified prior art (fetched and read directly, not guessed):
- Konrad Dybcio's mainline Linux device-tree work for Apple A7/A8/A8X
  explicitly names "iPhone 5S, 6 and 6 Plus" as supported, and has been
  upstreamed into mainline Linux (`arch/arm64/boot/dts/apple/`).
- [ivonblog.com's "Installing Linux on an iPhone 6" post](https://ivonblog.com/en-us/posts/iphone-6-postmarketos/)
  gives an iPhone-6-specific procedure, author tested on iOS 12.5.7
  (essentially our exact 12.5.8). Confirms nothing writes to storage, and
  reports real limitations: hit a kernel panic, called overall driver
  support poor (no touchscreen driver — needs a Lightning-to-USB OTG
  keyboard/mouse), and concluded it's "not practical" as a daily driver.
  Set expectations accordingly — a working desktop session is optimistic;
  boot log output is already a genuine milestone (matches what phase2
  achieved with framebuffer/console output on the real device).

## What's real and built so far (2026-09-08)

### 1. `pongo-linux-src/` — pongoOS fork with Linux-loading support

Cloned `github.com/konradybcio/pongoOS` (gitignored, not vendored — same
treatment as `phase2/pongo-src/`). This is a **different** pongoOS fork
from the one `phase2/` already builds (`checkra1n/PongoOS` upstream) —
this one adds `src/modules/linux/linux.c`, `src/shell/linux.c`, and
`scripts/load_linux.py`, none of which exist in the vanilla fork phase2
uses. Confirmed via `grep`, not assumed.

**Built successfully.** Toolchain gaps and exact fixes (this box is Kali,
not the Ubuntu 24.04 phase2's own README was written against, so the
specific package/tool versions differ, though the *pattern* — no root
available, work around via `apt-get download` + `dpkg-deb -x` into a
local prefix — is the same one already established for phase2 and
`emulator/`):

- `ld64`/`cctools-strip`: not in Kali's own apt repo. Fetched directly
  from checkra1n's own package repo (`assets.checkra.in/debian/Packages`,
  a flat-format repo — `curl`ing the `Packages` index directly works
  without adding an apt source, since that needs root). Picked the
  newest listed versions (`ld64_954.16-0`, `cctools-strip_949.0.1-2`).
- `ld64`'s transitive shared-lib deps not present on this box:
  `libxml2.so.2` (Kali ships `.so.16` — pulled Ubuntu Jammy's
  `libxml2_2.9.13+dfsg-1ubuntu0.12`, which itself needed `libicuuc.so.70`
  — pulled Ubuntu Jammy's `libicu70_70.1-2ubuntu1`), `libcrypto.so.1.1`/
  `libssl.so.1.1` (pulled Ubuntu Focal's `libssl1.1_1.1.1f-1ubuntu2.24`,
  the exact package phase2/README.md's own local-build notes already
  identified for this), `libBlocksRuntime.so.0` (Kali's own
  `libblocksruntime0` package, no external archive needed).
- `llvm-ar`/`llvm-ranlib`: pongoOS's newlib cross-build hardcodes the
  unversioned names (same known issue as phase2's own CI fix commit
  `01325e8`). This box has `llvm-21`, not `llvm-18` — symlinked
  `llvm-ar-21`/`llvm-ranlib-21` to unversioned names in a local prefix
  bin dir instead of `/usr/local/bin` (no root here either).
- LTO library path updated for llvm-21:
  `/usr/lib/llvm-21/lib/libLTO.so.21.1` (phase2's README references the
  llvm-18 path, doesn't apply on this box).

All of the above is captured in `~/.bashrc.phase3-kernel-env` (**outside
the repo, host-specific, not committed** — same treatment as
`~/.bashrc.emulator-env`). `source` it before touching this directory.

**Output** (in `pongo-linux-src/build/`, gitignored, reproducible via
`source ~/.bashrc.phase3-kernel-env && make all` after patching one known
upstream bug the same way phase2 already documented — a missing
`#include <stdarg.h>` in `src/kernel/task.c`, `clang`-version-dependent,
not this project's bug):
- `Pongo.bin` (676,192 bytes)
- `checkra1n-kpf-pongo` (87,824 bytes)
- `PongoConsolidated.bin` (764,032 bytes)

Confirmed `src/drivers/plat/s8000.c` registers the `s8000` platform driver
(the iPhone 6's SoC, in Apple's own AP-identifier naming — a different
naming convention from the Linux kernel's "T7000" chip-family name used
below, same physical chip).

### 2. `linux-apple/` — mainline-track Linux kernel with iPhone 6 support

Cloned `github.com/konradybcio/linux-apple` (shallow, `--depth 1`,
gitignored, not vendored — 2.2GB). **Confirmed exact-match device tree
exists**: `arch/arm64/boot/dts/apple/t7000-n61.dts` —

```
/*
 * Apple iPhone 6, N61, iPhone7,2 (A1549/A1586/A1589)
 * Copyright (c) 2022, Konrad Dybcio <konrad.dybcio@somainline.org>
 */
...
model = "Apple iPhone 6";
compatible = "apple,n61", "apple,t7000", "apple,arm-platform";
```

This isn't "A8 family, probably compatible" — it's the literal named
device tree for this exact phone (`N61`/`iPhone7,2`, matches the real
device's own `HardwareModel: N61AP` seen via `ideviceinfo` earlier this
session). Compiled clean via `dtc` during the kernel build (see below).

Config: `SoMainline/linux-apple-resources`' `example.config` (6,563
lines) — already sets `CONFIG_ARM64_4K_PAGES=y` by default (the A8
requirement the blog post calls out; A9+ needs 16K, not applicable here).
`make ARCH=arm64 LLVM=1 olddefconfig` ran clean after fixing toolchain
gaps beyond what pongoOS needed:

- `bison`/`bc`: not installed on this box at all (Kali doesn't ship them
  by default). Kali's own apt repo has them — `apt-get download` (no
  root) + `dpkg-deb -x` into the same local prefix.
- `bison` needs `BISON_PKGDATADIR` pointed at its extracted
  `usr/share/bison` (it doesn't auto-detect a relocated prefix) — added
  to `~/.bashrc.phase3-kernel-env`.
- `ld.lld`/`llvm-nm`/`llvm-objcopy` (unversioned): same story as
  `llvm-ar`/`llvm-ranlib` above — `lld-21` isn't installed by default
  either (only `llvm-21` proper), pulled via `apt-get download`,
  symlinked unversioned.

**Build status: genuinely in progress, not finished, cleanly resumable.**
`make ARCH=arm64 LLVM=1 -j2 Image.lzma dtbs` was run in five ~9-minute
increments (bounded by this session's own tool timeout, not a build
failure) and reached **2,311 compiled objects** across `mm/`,
`security/selinux/`, `fs/ext4/`, `net/` (core, ipv4, wireless, mac80211),
`drivers/` (video/fbdev, mfd, input, iio), with `t7000-n61.dtb` and every
other listed device tree already compiled successfully. No crash, no
`make` error at any point — every stop was `timeout`'s own SIGTERM
mid-compile. System memory was watched every round and stayed in a stable
200–850MB-free band the whole time (this box only has 3.7GB RAM and
dipped much lower earlier in the session during unrelated work) — no OOM,
no thrashing. **This box's `example.config` is a large, close-to-distro
config** (selinux, netfilter, ext4, mac80211, a wide driver set all
enabled) — a genuinely big build on 4 modest cores, not a quick one.

**To resume:** `source ~/.bashrc.phase3-kernel-env && cd
phase3/kernel/linux-apple && make ARCH=arm64 LLVM=1 -j2 Image.lzma dtbs`
— `make` is fully incremental, nothing already-built gets redone. Expect
to need several more multi-minute rounds before `arch/arm64/boot/Image.lzma`
exists. Consider trimming `example.config` (`make ARCH=arm64 LLVM=1
menuconfig`, disable selinux/netfilter/wifi/most drivers we don't need
for a console-only or netboot-only target) if faster iteration matters
more than matching the upstream reference config exactly.

## Update 2026-09-08 (2): kernel build finished

Resumed and completed. Real, verified outputs:

- `linux-apple/arch/arm64/boot/Image.lzma` — 7,113,836 bytes.
- `linux-apple/dtbpack` — 260,992 bytes, built via
  `raw.githubusercontent.com/SoMainline/linux-apple-resources/master/dtbpack.sh`
  (copied into `linux-apple/`, run from there since its `DTBPATH` is
  relative). Confirmed the `N61` marker is actually present in the packed
  blob (`Cows`-prefixed format the script writes) — not just "the script
  exited 0".

No `make` errors at any point in the final resume — this really was just
a slow build on 2 jobs / modest hardware, exactly as flagged before.

## Not yet started

- **`phase3/rootfs/`**: config wizard finished successfully (device
  `apple-idevice`, not `apple-iphone6` — see `phase3/rootfs/README.md`
  for why), but `pmbootstrap`'s actual chroot/build operations are
  blocked on needing interactive `sudo`, which this box doesn't have
  passwordless. See `phase3/rootfs/README.md` for the exact resume point.
- **Any real device/USB/DFU interaction.** Deliberately not attempted —
  needs interactive `sudo` and, after the `phase3/ramdisk/` incident
  earlier this project, live-device steps get done with direct user
  supervision, not by an unattended process. The eventual live command
  (once `Image.lzma` + `dtbpack` + an initramfs/rootfs all exist) is
  `python3 pongo-linux-src/scripts/load_linux.py -k
  linux-apple/arch/arm64/boot/Image.lzma -d linux-apple/dtbpack -r
  <initramfs>`, run against a live pongoOS session the same way
  `phase2/tools/omerta_load.py` already is.

## Update 2026-09-08 (3): live device test attempted — kernel doesn't boot cleanly yet

`phase3/rootfs/` finished (see that README — `install`/`initfs`/`export`
all completed, real initramfs/rootfs/vmlinuz produced). With the user
present and DFU/`checkra1n` handled directly by them (this project's
standing rule for any real-device step): booted this directory's own
`pongo-linux-src` `Pongo.bin` (confirmed live pongoOS session, `05ac:4141`
in `lsusb`), then ran

```
python3 scripts/load_linux.py \
  -k linux-apple/arch/arm64/boot/Image.lzma \
  -d linux-apple/dtbpack \
  -r <pmbootstrap's exported initramfs>
```

**Result: the phone's screen went black, then the pongoOS USB session
disconnected and never re-enumerated as anything (no netboot USB-network
interface appeared either). The phone came back up at iOS's Setup
Assistant / Activation Lock screen** — `ideviceinfo` confirmed this is
**the same already-erased state from the `phase3/ramdisk/` incident**
(identical `BuildVersion: 16H88`, `ActivationState: Unactivated`,
`BrickState: true`, same UDID) — not a new or worse state. No new NAND
writes are believed to have occurred.

**Best-understood explanation:** the Linux kernel likely panicked or
hung very early (before/during display init), which triggered a hardware
reset; on any hard reset the device falls back to iBoot's normal boot
chain, and since the real NAND-stored iOS was already left erased and
Setup-Assistant-pending from the earlier incident, that's what
resurfaced — not a new erase, the same one surfacing again after a
reset. This matches the ivonblog.com reference author's own reported
experience on this exact device generation ("hit a kernel panic",
"almost every hardware feature has an X" in the compatibility table) —
we did not get further than they did, and possibly hit the same
underlying issue.

**Not diagnosed further this session:** no serial/earlycon console was
attached, and phase2's own established "framebuffer, not USB, is the
real console" pattern wasn't confirmed working for this Linux kernel
build specifically (it may need `earlycon`/framebuffer driver
verification, or the display handoff from pongoOS's own console may not
match what this kernel's simple-framebuffer driver expects). This is a
real, unresolved technical gap, not something worked around.

## If this is picked up again

1. ~~Resume the kernel build~~ / ~~get phase3/rootfs/ past its sudo
   blocker~~ — **all done, see above and phase3/rootfs/README.md.**
2. ~~Live device test~~ — **attempted, kernel doesn't reach visible
   boot output, see above.** Before repeating this exact test, consider:
   - Adding `earlycon` to the kernel cmdline (`load_linux.py -c`) to get
     any console output earlier in boot, before framebuffer/display
     drivers would normally init.
   - Checking whether `CONFIG_FB_SIMPLE`/the actual apple-specific
     display driver is enabled in `example.config` and whether pongoOS's
     own console hand-off address matches what this specific kernel
     build expects.
   - Trying a much smaller/`console`-only kernel config (trim
     selinux/netfilter/wifi/most drivers per the earlier note) to rule
     out an unrelated init-time crash in a driver we don't even need.
   - Re-reading `ivonblog.com`'s post for exactly where in the boot
     sequence their kernel panic happened, if that detail exists there.
3. Each live-device attempt should be done with the user present, same
   as this one — no change to that rule.
