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

## Update 2026-09-08 (4): earlycon debugging — confident cmdline found, no rebuild needed

Investigated why the boot produces no visible output at all (not just
"wrong framebuffer" — genuinely nothing, on either a display or a
console). Real findings, all confirmed by reading the actual device tree
and kernel source, not guessed:

**There is no framebuffer node anywhere in the A7-A8X (`t7000`) device
trees.** Checked `t7000-n61.dts`, `t7000-6.dtsi`, and `t7000.dtsi`
directly: no `simple-framebuffer` compatible node, no `chosen {
stdout-path }` at all — the `chosen` node in `t7000.dtsi` only sets
`#address-cells`/`#size-cells`/`ranges`. For comparison,
`arch/arm64/boot/dts/apple/t8103-jxxx.dtsi` (the M1 Mac Mini family, a
much further-along port in this same kernel fork) *does* have
`stdout-path = "serial0"` — the t7000/A8 port genuinely doesn't wire up
a console yet, at the device-tree level, at all. This alone would fully
explain a silent boot even if the kernel is otherwise running fine:
`CONFIG_FB_SIMPLE=y` is enabled in `.config`, but it has nothing to
attach to without a framebuffer node.

**But there is a real, enabled, earlycon-capable UART.**
`t7000.dtsi` defines `serial0: serial@20a0c0000` with `compatible =
"apple,s5l-uart"`, `reg = <0x2 0x0a0c0000 0x0 0x4000>` (i.e. MMIO base
`0x20a0c0000`), `reg-io-width = <4>` — and `t7000-6.dtsi` turns it on for
the iPhone 6 specifically (`&serial0 { status = "okay"; }`, no comment,
unlike every other serial node which is labeled Bluetooth/baseband/etc. —
consistent with serial0 being the generic/debug UART). Confirmed in
`drivers/tty/serial/samsung_tty.c`:
```
OF_EARLYCON_DECLARE(s5l, "apple,s5l-uart", apple_s5l_early_console_setup);
```
Apple's S5L UART is close enough to Samsung's S3C2410 IP block that it
reuses the same driver (the driver's own comment says as much). Traced
`setup_earlycon()` in `drivers/tty/serial/earlycon.c`: it matches
`earlycon=<name>,...` against the name registered via
`OF_EARLYCON_DECLARE`'s first argument (here, `s5l`) directly from the
kernel command line — **this does not depend on `stdout-path` being set
in the device tree at all**, so the missing `chosen` entry doesn't block
it. `reg-io-width = <4>` maps to the `mmio32` earlycon address-space
spec. The driver name for the later (post-earlycon) console is
`ttySAC0` (from `S3C24XX_SERIAL_NAME "ttySAC"` in the same file).

**Confident earlycon spec:** `earlycon=s5l,mmio32,0x20a0c0000
console=ttySAC0`

**No rebuild was needed** — checked `.config` directly:
`CONFIG_SERIAL_EARLYCON=y`, `CONFIG_SERIAL_SAMSUNG=y`,
`CONFIG_SERIAL_SAMSUNG_CONSOLE=y` are all already set. The existing
`Image.lzma` (7,113,836 bytes, unchanged) already has this driver built
in.

Also checked `pongo-linux-src/scripts/load_linux.py`'s `-c`/`--cmdline`
handling and `src/shell/linux.c`'s `linux_cmdline` command: `-c` sends
`linux_cmdline <string>\n` to pongoOS before boot, which does a plain
`memcpy` into the buffer passed to Linux as `bootargs` — a clean
replace, nothing to conflict with (the dtbpack doesn't set its own
`bootargs` either).

**Exact next live-device command** (only the `-c` argument is new):
```
python3 scripts/load_linux.py \
  -k linux-apple/arch/arm64/boot/Image.lzma \
  -d linux-apple/dtbpack \
  -r <pmbootstrap's exported initramfs> \
  -c "earlycon=s5l,mmio32,0x20a0c0000 console=ttySAC0"
```

**What this will and won't tell us:** if boot text appears, we now have
a real console and can actually see where/why it panics or hangs (if it
still does) — a huge diagnostic upgrade from a black screen. If *still*
nothing appears even with this earlycon spec, that's itself a real
finding: it would mean the failure happens before the kernel's own
console/earlycon init code runs at all (e.g. very early boot assembly,
an MMU/exception-level setup fault — the Hackaday writeup on this same
kernel fork's A7/A8/A8X bring-up specifically flagged the MMU-enable
sequence as the thing that blocked progress for over a year on other
devices in this family, so an early-EL/MMU-stage fault on this
specific device is a real possibility, not a remote one) — narrowing the
problem rather than resolving it. Not rebuilt, not tried against real
hardware, this session — per this project's standing rule, that's the
next live-device step, done with the user present.

Not independently re-verified against `ivonblog.com`'s post for a more
specific panic location — the device-tree/kernel-source evidence above
is more concrete and specific to this exact build than what that post is
likely to add, so re-fetching it wasn't judged worth the time this round.

## Update 2026-09-08 (5): earlycon attempt gave no new signal — likely pre-console failure

With the user present, re-ran the exact same live test with
`-c "earlycon=s5l,mmio32,0x20a0c0000 console=ttySAC0"` added. **Identical
observable outcome to the first attempt**: screen went black, the
pongoOS USB session disconnected and didn't re-enumerate as anything for
several seconds, then the phone came back up at Setup Assistant — same
already-known erased state, confirmed by USB re-enumerating as normal
`05ac:12a8` iPhone mode again, no new damage.

**This result is genuinely ambiguous, not a confirmed dead end**, because
there's no way to physically observe the UART-based `earlycon` output
from this host — it goes to a physical pin, not the screen or over USB.
So we cannot distinguish between "earlycon printed something useful but
we have no way to see it" and "the crash happens before earlycon's own
init code ever runs." The identical black-screen/USB-disconnect pattern
in both attempts is circumstantial evidence for the latter (if the kernel
had gotten meaningfully further with a working console, some visible
side effect — even just surviving a bit longer before the USB drop —
might be expected, though this isn't proof) — consistent with the
pre-console MMU/early-boot-assembly failure class flagged as the next
real lead in Update (4).

**Where this leaves phase3/kernel: two live-hardware attempts, same
result, no new hardware-observable data from the second one.** Further
progress from here needs one of:
- **Physical UART access** — soldering/probing an actual hardware debug
  point on the phone to capture real earlycon bytes. This is a real
  hardware-modification undertaking with its own risk to the device, not
  a software step, and wasn't attempted or scoped further this session.
- **Deep kernel source-level investigation** of the A7/A8 MMU/early-boot
  path (comparing this fork's boot assembly against whatever fix the
  Hackaday-covered A7/A8/A8X bring-up breakthrough actually changed) —
  genuinely open-ended, matches `PLAN.md`'s own "multi-month research
  project" framing for this whole tier, not a quick next step.

Given two consecutive identical live-device outcomes, further live DFU
cycles right now don't have new diagnostic leverage without one of the
above first. Recommend pausing live-hardware iteration here and treating
any further work as offline kernel/source research, resuming live testing
only once a concrete new hypothesis (from either avenue above) exists to
test.

## If this is picked up again

1. ~~Resume the kernel build~~ / ~~get phase3/rootfs/ past its sudo
   blocker~~ — **all done, see above and phase3/rootfs/README.md.**
2. ~~Live device test~~ / ~~earlycon retest~~ — **both attempted, both
   ended in the same black-screen/USB-disconnect/reset-to-Setup-Assistant
   pattern, no new hardware-observable data from the earlycon addition
   alone. Not proof of a pre-console failure, but the best-supported
   explanation. See Update (5) above.**
3. Two real paths forward, neither a quick follow-up: physical UART
   hardware access (real device-modification risk, out of scope without
   explicit new authorization), or deep source-level comparison of this
   kernel fork's A7/A8 early-boot/MMU-enable assembly against the known
   Hackaday-covered fix for other devices in this chip family.
4. Don't repeat the live-device test again without a concrete new
   hypothesis from #3 to test — two identical results in a row means
   another identical attempt is unlikely to teach us anything new.
