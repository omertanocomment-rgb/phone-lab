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
not this project's bug). Two more clang-21-vs-older-clang strictness fixes
needed to get a clean `make all` again after a host environment reset
(`ld64`'s own apt deps — `libxml2`/`libssl1.1`/`libicu70`/
`libblocksruntime0` — had also been fully uninstalled by the same reset;
reinstalled from the already-cached `.deb`s in `~/phase3-kernel-deps/` in
dependency order): `src/kernel/mm.c` had two genuinely-dead local
variables (`vm_index_start`, a shadowed local `is_tt1`) that only newer
clang flags as `-Werror`-fatal, silenced with
`__attribute__((unused))`; `src/drivers/sep/sep.c` had a stale
forward-declaration of `sep_help()` with the wrong signature (real
definition takes `(const char*, char*)`), which newer clang's C23-leaning
diagnostics now reject — corrected the declaration to match. Neither
touches this project's own logic, both are upstream pongoOS quirks:
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

## Update 2026-09-08 (6): found and patched a real x0/FDT handoff bug — untested on hardware

**Correction to earlier documentation:** `src/drivers/plat/s8000.c` is
**not** the iPhone 6's platform driver — its own source names it
`"Apple A9 (S8000, Samsung)"` (the iPhone 6s' chip, not the iPhone 6's).
The actual matching driver for our device is `src/drivers/plat/t7000.c`
(`device->cpid == 0x7000`), confirmed alongside the device tree's own
`compatible = "apple,t7000"`. An earlier update in this file misattributed
`s8000.c` to this project's device; this doesn't change any conclusion
already reached, just corrects the record.

**Investigated whether `fix_a7()` (applied to our device via
`apply_tunables()`'s `case 0x7000: case 0x7001: fix_a7(); break;`) is a
tunable mismatch** — it isn't. Its own code comment reads "Cyclone /
typhoon specific init thing": Cyclone is A7's microarchitecture, Typhoon
is A8's, so this function intentionally covers both chip generations
under one name. Ruled out as a cause.

**Found the actual bug, by tracing the real jump-into-Linux path end to
end:**

`pongo_entry()` (`src/kernel/entry.c`) branches on `gBootFlag`, and for
`BOOT_FLAG_LINUX` previously fell through to one shared final call used
by *every* boot path:
```c
exit_to_el1_image((void*)gBootArgs, gEntryPoint);
```
`gBootArgs` is XNU's `boot_args` structure. `exit_to_el1_image` →
`stage3_exit_to_el1_image` → `jump_to_image(entry, args)`
(`src/boot/jump_to_image.S`) does `mov x0, x1` — i.e. whatever's passed
as `args` becomes x0 at the final jump, unconditionally, for both the
Linux and XNU paths.

**The ARM64 Linux boot protocol requires x0 to be the physical address of
the device tree blob** (FDT magic `0xd00dfeed`), not an XNU `boot_args`
struct. `linux_prep_boot()` (`src/modules/linux/linux.c`) already builds
exactly the right FDT in `gLinuxFDT` — complete with the injected
`simple-framebuffer` node (see Update 4's correction below), initrd
pointers, and our `-c` cmdline/earlycon spec — but **that pointer was
never passed to Linux at all**. Linux was being jumped into with x0
pointing at an XNU structure it has no way to interpret as a device tree.
This one bug would fully and simply explain **every** symptom observed
across both live tests: a crash before any code (console, earlycon, or
otherwise) could run, identical between the plain and earlycon attempts
(the earlycon spec lives *inside* the unreachable `gLinuxFDT`'s
`bootargs` property — the kernel never got a chance to read it either).

**Correction to Update (4)'s framebuffer conclusion, found while tracing
this:** `linux_dtree_overlay()` in the same file *does* inject a real
`simple-framebuffer` node at boot time, using pongoOS's own live,
visually-confirmed-working framebuffer address/format — Update (4)'s
"no framebuffer node anywhere" claim was only true of the static `.dts`
files, not this runtime injection. Verified the injected `format` string
(`"a8b8g8r8"`) is a real, recognized `SIMPLEFB_FORMATS` entry in
`linux-apple`, and `CONFIG_FB_SIMPLE=y`/`CONFIG_FRAMEBUFFER_CONSOLE=y`
are both already set — so if the kernel had gotten past early boot, a
working on-screen console was actually plausible. This doesn't change
the live-test outcome (nothing appeared either way), but it does mean the
x0/FDT bug above, not a missing framebuffer, is the best-supported
explanation for the total silence.

**Fix applied** (`src/kernel/entry.c`, `pongo-linux-src`), rebuilt
successfully (`make all`, no errors, `build/Pongo.bin` regenerated,
676,192 bytes, 2026-09-08 08:52):
```c
else if(gBootFlag == BOOT_FLAG_LINUX)
{
    linux_boot();
    // physical address of gLinuxFDT (same cacheable-view rebase as
    // gLinuxStage already gets a few lines up), not gBootArgs
    extern void *gLinuxFDT;
    exit_to_el1_image((void*)(((uint64_t)gLinuxFDT) - kCacheableView + 0x800000000), gEntryPoint);
}
else
{
    tz_lockdown();
    xnu_boot();
    exit_to_el1_image((void*)gBootArgs, gEntryPoint);
}
```
(The old unconditional `exit_to_el1_image((void*)gBootArgs, gEntryPoint);`
after the if/else chain was removed — each branch now calls it with the
correct argument for what it's actually booting.)

**Not tested on real hardware this pass** — per this project's standing
rule, live-device steps happen with the user present, and this task was
scoped to offline research/patching only. This is a well-reasoned,
concretely-sourced fix (not a guess), but it is unverified until run
against the real phone. If it's right, the very next live test should
show either genuine kernel boot log text (framebuffer console or
earlycon UART) or at minimum a different failure signature than the
identical black-screen/USB-disconnect pattern seen twice before — either
outcome would be new information. If the phone still shows the exact
same silent failure a third time, this hypothesis would be substantially
weakened and the next lead would need to go back to the MMU/early-boot
assembly path proper.

## Update 2026-09-08 (7): x0/FDT fix tested — same identical failure a third time

With the user present, repeated the live test using the rebuilt,
patched `Pongo.bin` — same DFU → `checkra1n -c -k .../pongo-linux-src/build/Pongo.bin
-E` → `load_linux.py` sequence, same kernel/dtbpack/initramfs/cmdline.
**Result: identical to both prior attempts.** Screen went black, pongoOS
disconnected, phone came back up at the same Setup Assistant/Activation
Lock state, confirmed via `lsusb` (`05ac:12a8`, normal mode). No new
damage, no new visible signal.

**This means the x0/FDT handoff bug, while real and correctly fixed, was
not the (or not the only) cause of the silent failure.** Three
consecutive identical live-device outcomes across three genuinely
different hypotheses (plain boot, +earlycon, +x0/FDT fix) is a strong
signal that the actual failure point is earlier and more fundamental than
any of these — most likely the MMU/exception-level early-boot-assembly
class of problem flagged back in Update (5), which sits *before* the
kernel would ever read a device tree, use a UART, or care what's in x0
for its own console/earlycon setup. A wrong FDT pointer would matter once
the kernel gets far enough to dereference it — if the crash is earlier
than that, the fix, though real, never got a chance to matter.

**Not done yet, and genuinely substantial if picked up:** verifying the
`gLinuxFDT`/`gLinuxStage` rebase math for a subtle error (a plausible
but unconfirmed alternate explanation — worth checking before assuming
the MMU path), and the actual MMU/early-boot-assembly investigation
itself, which needs comparing this exact kernel fork's boot assembly
(`arch/arm64/kernel/head.S` / equivalent early entry code) against
whatever Konrad Dybcio's real fix was for other devices in this chip
family — not established with certainty in Update (6)'s research pass.

## Update 2026-09-08 (8): offline sanity check found a second, real FDT bug — untested on hardware

Picked up item #2 from the previous checklist (verify the `gLinuxFDT`
rebase arithmetic) as a scoped, offline-only task — no live device
touched. It surfaced more than a rebase-math slip: a second, distinct bug
in the same handoff path, independent of the one fixed in Update (6).

**The bug:** `linux_prep_boot()` (`src/modules/linux/linux.c`) computes
`gLinuxFDT` as an offset into the *staging buffer* `alloc_contig()`
returned (`gLinuxStage`'s original value, before that variable itself
gets rebased a few lines later at `linux.c:343`). But `linux_boot()`
(called right before the `exit_to_el1_image` handoff in `entry.c`) does
`memcpy(gEntryPoint, gLinuxStage, gLinuxStageSize)` — physically
relocating the *entire* kernel-image+FDT blob from that staging buffer to
the real boot address `gEntryPoint` (`0x803000000`). `gLinuxStageSize`
already includes the FDT (`image_size + LINUX_DTREE_SIZE`), so the FDT
bytes really do get copied to `gEntryPoint + image_size_aligned` — but
`gLinuxFDT` itself was never updated to point there. Update (6)'s fix
correctly converted `gLinuxFDT`'s *addressing scheme* (cacheable VA →
physical), but that only fixed how to interpret the pointer, not that the
pointer's target had since been superseded by the relocation. The x0
handed to Linux still pointed at the pre-copy staging location — whether
that memory remains mapped/valid at the point Linux's own MMU-off early
boot code tries to read it is unknown, but it's certainly not where the
kernel expects to find *its own* device tree relative to where it was
actually loaded.

Notably, the existing code already computes the *correct* pattern one
line above, for a variable that turns out to be otherwise unused on the
Linux path: `gBootArgs = (gEntryPoint + image_size + 7) & -8` — this is
exactly the right formula (offset from `gEntryPoint`, not from the
staging buffer), just never wired up for the FDT.

**Fix applied** (`src/modules/linux/linux.c`, `src/kernel/entry.c`,
`pongo-linux-src`): added a new global `gLinuxFDTFinal`, computed
immediately after `gLinuxFDT` and before `gLinuxStage`'s rebase, using
the same `(gEntryPoint + image_size + 7) & -8` formula as the existing
(dead-for-Linux) `gBootArgs` line. `entry.c`'s `BOOT_FLAG_LINUX` branch
now passes `gLinuxFDTFinal` directly (already in `gEntryPoint`'s
addressing scheme, no further rebase needed) instead of re-deriving a
physical address from the stale `gLinuxFDT`. Rebuilt clean (`make all`,
`build/Pongo.bin` regenerated, 676,192 bytes, 2026-09-08 10:52) after
also resolving the environment/toolchain drift noted above (`ld64` and
its deps had to be reinstalled from cache; two clang-21 strictness fixes
in `mm.c`/`sep.c` — see that section).

**Not tested on real hardware this pass** — per this project's standing
rule, live-device steps happen with the user present, and this task was
explicitly scoped to the offline sanity check only. This is a concrete,
well-sourced bug with a very plausible causal story for the identical
silent failures seen across all three prior live attempts (a bad/orphaned
FDT pointer would explain a hang regardless of whether the crash is
"early" or "late" in Linux's boot, since it doesn't require MMU/assembly
involvement at all — a much simpler explanation than the MMU/early-boot
theory Updates (5) and (7) were leaning toward). If the next live test
still shows the identical black-screen/USB-disconnect signature a fourth
time, that would be a genuinely strong result — it would mean neither of
the two real, distinct FDT bugs found so far was the actual cause, and
the MMU/early-boot-assembly path from Update (5) would become the clear
leading hypothesis.

## Update 2026-09-08 (9): offline MMU/early-boot investigation found a THIRD real bug — a heap buffer overflow in kernel decompression — untested on hardware

Picked up the Update (5)/(7) "MMU/early-boot-assembly" lead as a scoped,
offline-only task (no live device touched). Before diving into ARM64
`head.S`-equivalent assembly comparison, first researched what actually
unblocked Konrad Dybcio's own upstream A7/A8/A8X bring-up (the
[Hackaday-covered breakthrough](https://hackaday.com/2022/06/12/boot-mainline-linux-on-apple-a7-a8-and-a8x-devices/)
referenced since Update (5)): his own account is that the MMU-enable
blocker turned out to be **"a single line difference in how they loaded
the Linux image"** — not an MMU/assembly bug at all. That pointed the
search back at this project's own kernel-image loading path
(`linux_prep_boot()`/`linux_boot()` in
`pongo-linux-src/src/modules/linux/linux.c`) rather than genuine
ARM64 early-boot assembly.

**The bug:** `linux_prep_boot()` sizes the kernel staging buffer off the
**compressed** `Image.lzma` payload size —
`gLinuxStage = alloc_contig(image_size + LINUX_DTREE_SIZE)`, where
`image_size` at that point is still `loader_xfer_recv_count` (the
compressed upload size, ~7MB per Update (3)'s build) — but then bounds
the LZMA decompressor with a **hardcoded `dest_size = 0x10000000`**
(256MiB), independent of what was actually allocated:
```c
size_t dest_size = 0x10000000;
...
gLinuxStage = (void *)alloc_contig(image_size + LINUX_DTREE_SIZE);
ret = unlzma_decompress((uint8_t *)gLinuxStage, &dest_size, loader_xfer_recv_data, image_size);
```
`unlzma_decompress()`'s `dest_size` is `LzmaDec`'s `dicBufSize` — the
actual bound the decoder writes within
(`p.dicBufSize = outSize;` in `src/lib/lzma/lzmadec.c`). A real arm64
`Image` decompresses to several times its compressed size, so
`LzmaDec_DecodeToDic` was free to write tens of MB **past the end of a
buffer sized for only ~9MB** — a genuine heap buffer overflow, executing
in pongoOS's own C code while its MMU/scheduler are still live, **before
Linux is ever jumped into**. This fully explains the totally silent,
identical black-screen/USB-disconnect failure seen across all three
prior live attempts even after two real, correctly-reasoned FDT-handoff
fixes (Updates 6 and 8): the crash was never in the handoff at all — it
happened earlier, corrupting heap state during kernel decompression
itself, which is also why neither FDT fix changed the observed outcome.

**Fix applied** (`src/modules/linux/linux.c`, `pongo-linux-src`): the
classic `.lzma` alone-format header is `[5-byte props][8-byte LE
uncompressed size][compressed data]` — matching this file's own
`propsize = LZMA_PROPS_SIZE(5) + 8` framing exactly. Read the real
uncompressed size from that header up front and size both the allocation
and the decompressor's bound off it, instead of guessing:
```c
uint64_t uncompressed_size = *(uint64_t *)(loader_xfer_recv_data + LZMA_PROPS_SIZE);
gLinuxStage = (void *)alloc_contig(uncompressed_size + LINUX_DTREE_SIZE);
dest_size = uncompressed_size;
ret = unlzma_decompress((uint8_t *)gLinuxStage, &dest_size, loader_xfer_recv_data, image_size);
```
Also hardened the "not actually compressed" fallback branch (`ret !=
SZ_OK`, i.e. a raw pre-decompressed `Image` was uploaded instead): that
branch's own `image_size` comes from a different header offset entirely,
so the LZMA-header-derived allocation above can't be trusted to have
sized `gLinuxStage` correctly for it — added an explicit re-`alloc_contig`
before the `memcpy` if the raw image turns out bigger than what was
allocated for the LZMA-path guess, so this branch can't overflow either
regardless of which size guess was actually right.

Rebuilt clean (`make all`, no errors, `build/Pongo.bin` regenerated,
676,192 bytes, 2026-09-08 12:18).

**Not tested on real hardware this pass** — per this project's standing
rule, live-device steps happen with the user present, and this task was
scoped to offline research only. This is a concrete, well-sourced bug
(confirmed by reading `unlzma_decompress()`'s actual bound semantics in
`lzmadec.c`, not guessed) with a very plausible causal story for all
three identical prior failures — a much simpler, earlier-firing
explanation than the MMU/early-boot-assembly theory Updates (5) and (7)
were leaning toward, and one that doesn't require any ARM64 assembly
comparison work at all. If the next live test still shows the identical
black-screen/USB-disconnect signature a fourth time, that would be a
genuinely strong result: it would mean none of the three real, distinct
bugs found across Updates (6), (8), and (9) was the actual cause, and the
MMU/early-boot-assembly path would become the clear remaining lead.

## Update 2026-09-08 (10): Update (9) fix retested live — identical failure a fourth time

Live test with the user present, using `build/Pongo.bin` with the Update
(9) decompression-overflow fix applied (still also containing the Updates
(7)/(8) FDT-handoff fixes). Sequence: `usbfs_memory_mb` bumped to 512,
`sudo checkra1n -c -k build/Pongo.bin -E` (succeeded, device re-enumerated
as pongoOS `05ac:4141`), then `sudo python3 scripts/load_linux.py -k
Image.lzma -d dtbpack -r <pmbootstrap initramfs> -c
"earlycon=s5l,mmio32,0x20a0c0000 console=ttySAC0"`. All four transfer
stages (ramdisk, fdt, kernel, `bootl`) completed and reported success from
the script's own perspective (a caught disconnect on `bootl`'s ctrl
transfer, which the script treats as the expected success signature).

**Result: identical outcome to all three prior live attempts.** Device
disconnected from pongoOS and re-enumerated a few seconds later as normal
iOS (`05ac:12a8`), confirmed via `ideviceinfo` to be the exact same
known-erased baseline from the original ramdisk incident (`BuildVersion:
16H88`, `ActivationState: Unactivated`, `BrickState: true`, same
HardwareModel/ChipID) — no new or additional damage, just the same
fallback signature a fourth time.

**This is the strong result flagged as possible in Update (9):** none of
the three real, distinct, well-sourced bugs found and fixed across
Updates (6), (8), and (9) — two independent FDT/x0-handoff issues plus a
genuine kernel-decompression heap buffer overflow — changed the observed
failure at all. That means the actual blocker sits at or before all of
that code ever runs, which points squarely at the MMU/early-boot-assembly
class of problem flagged since Update (5), or a failure mode invisible to
USB-side observation entirely (matching Konrad Dybcio's own account that
other devices in this chip family needed real assembly-level fixes, not
just data-handling fixes like the three found here).

[See Update (11) below — the MMU-off theory in this paragraph was
subsequently traced and disproven; pongoOS already disables the MMU
correctly for every boot path via `lowlevel_cleanup()`.]

## Update 2026-09-08 (11): two more hypotheses chased to ground (one real-but-harmless fix, one disproven) + a major reframing from upstream history

Offline-only session (device untouched). Full writeup with code excerpts
above this section; summary:

- **`gBootArgs` global-pointer corruption in `linux_prep_boot()`:**
  real bug (a leftover reassignment later dereferenced unconditionally at
  `entry.c:360`), but exhaustively traced to be harmless in practice — the
  corrupted value (`gFramebuffer`) is never read again before the Linux
  jump, and the address itself doesn't even fault (it falls inside
  pongoOS's own identity-mapped RWX window). **Fixed anyway** (cheap,
  correct, removes a landmine for future changes) but **not the cause**
  of the four observed failures.
- **MMU left on during the jump:** disproven. `lowlevel_cleanup()`
  already calls `cache_clean_and_invalidate()` over all of RAM and then
  `disable_mmu_el1()` (a correct SCTLR_EL1.M clear + TLBI + icache
  invalidate) for every boot path, satisfying the arm64 boot protocol's
  mandatory preconditions before `jump_to_image` ever runs. No fix
  applied; this closes out Update (5)'s original theory as stated.
- **Found Konrad Dybcio's actual upstream breakthrough commit**
  (`pongo-linux-src`'s own `origin` is `konradybcio/pongoOS` — real, deep
  git history, not a shallow clone): `5aabd49 "Linux."`, the literal
  "single line difference" the Hackaday piece quoted —
  `gEntryPoint = 0x800080000` → `0x803000000`. **This project's code
  already has that exact value** — the historic fix was already
  inherited, nothing new to apply.
- **The load-bearing new finding:** that same breakthrough commit's own
  message stated *"only supported on iPhone 7 for now... behavior on
  non-A10 devices is undefined!!"*, and a full scan of every Linux-module
  commit since (`git log --oneline --all -i --grep="a7\|a8\|t7000\|
  t7001\|8960"` across all 185 commits) turns up **zero** that validate
  or fix loader-side behavior for A7/A8/A8X — every post-breakthrough
  commit targets A10/A11-family hardware (iPhone 7, iPhone 8, iPad Pro,
  iPhone X). The kernel *device tree* has real upstream A8/T7000 support
  (`t7000-n61.dts`, found earlier in `konradybcio/linux-apple`), but the
  *loader* this project chainloads through has apparently **never been
  run against A7/A8/A8X hardware by anyone**, upstream or otherwise.

Rebuilt clean (`make clean && make all`, `build/Pongo.bin`, 676,192
bytes, 2026-09-08 13:20). Not live-tested this pass — the fix applied
isn't expected to change the outcome (it was traced as harmless), so
there's no new reason to expect a 5th live attempt to behave differently
yet.

## Update 2026-09-08 (12): checked `gEntryPoint` against the real T7000 memory map — found it's correct, but found the ACTUAL bug instead (LZMA "unknown size" sentinel)

User asked specifically to check `gEntryPoint` placement against the real
T7000 memory map. Read `t7000.dtsi`/`t7000-n61.dts` directly
(`konradybcio/linux-apple`, the same author as the loader): `system_memory`
confirms 1GiB RAM at `0x800000000` ("All A8 devices come with at least
1 GiB of RAM"), and a `reserved-memory` node named `hacky_reserved_mem`
reserves exactly `[0x800000000, 0x803000000)` — 48MiB — with the candid
comment *"TODO: include proper reservations, this makes it at least
boot.."*. That upper bound is byte-for-byte the same address as this
project's `gEntryPoint`. Traced `gEntryPoint`'s own history in
`pongo-linux-src` (commit `2796b5e "linux: reserve stuff properly +
cleanups"`, 2022-09-24): it's a deliberate fixed placement chosen to land
right after this same low-memory reservation, with SEPFW separately
reserved dynamically from the device's own ADT. **Conclusion: `gEntryPoint`
placement is correct and consistent with the real T7000 memory map — this
hypothesis is closed, not the cause.**

While confirming that, found the actual bug: checked what the real
`Image.lzma` this project builds looks like at the byte level.
```
$ xxd -l 16 -p arch/arm64/boot/Image.lzma
5d00000004ffffffffffffffff000f88
```
`5d 00 00 00 04` is the standard LZMA properties (lc/lp/pb + 64MiB
dictionary size). The next 8 bytes — the alone-format header's
"uncompressed size" field, which Update (9)'s fix reads directly — are
`ff ff ff ff ff ff ff ff`. **That's not a real size; it's the standard
LZMA "size unknown" sentinel**, written whenever the encoder is fed a
stream instead of a file with a known length up front (exactly how a
piped `xz --format=lzma`/`lzma` kernel build step normally runs). Update
(9)'s fix trusts this field unconditionally:
```c
uint64_t uncompressed_size = *(uint64_t *)(loader_xfer_recv_data + LZMA_PROPS_SIZE);
gLinuxStage = (void *)alloc_contig(uncompressed_size + LINUX_DTREE_SIZE);
dest_size = uncompressed_size;
```
With `uncompressed_size = 0xFFFFFFFFFFFFFFFF`, the allocation size wraps
around the 64-bit boundary to `~0x1FFFFF` (**~2MiB**) — while `dest_size`
(the decompressor's own output-buffer bound) keeps the full sentinel
value. Checked the real uncompressed kernel this project actually built
(`arch/arm64/boot/Image`, still on disk from the earlier build): **23.87
MiB on disk, 24.38 MiB per its own embedded header field** — over 10x
bigger than the ~2MiB buffer Update (9)'s "fix" actually allocates for
it. This either overflows that undersized buffer during decompression, or
(if `LzmaDec`'s internal bound-checking clamps and truncates instead —
`lzmadec.c:791` has a `dicBufSize`-clamping path) fails and falls through
to the code's own `puts("Assuming decompressed kernel.")` branch, which
then treats the still-compressed LZMA bytes as a raw pre-decompressed
`Image` and boots that garbage. **Either mechanism is a 100%-reproducible,
silent, pre-Linux failure on literally every attempt with this exact
kernel file** — fully explaining why Update (9)'s fix changed nothing
across all four live tests: it replaced one overflow (9MiB buffer, 256MiB
bound) with a worse one (2MiB buffer, ~18-exabyte bound), not an actual
fix for how this kernel's `Image.lzma` is really encoded.

**Fix** (`linux.c`): validate the header's uncompressed-size field before
trusting it — reject the sentinel (`UINT64_MAX`), reject zero, reject
anything implausibly large — and fall back to a fixed, generous 64MiB
bound (over 2.5x the real ~24MiB kernel, matching this same header's own
64MiB LZMA dictionary size) whenever the header can't be trusted. This
keeps the precise-size path for any future kernel image that *does*
carry a real size, while making this project's actual kernel (and any
other stream-compressed one) safe by construction instead of by luck.

Rebuilt clean (`make all`, no errors/warnings, `build/Pongo.bin`, 676,192
bytes, 2026-09-08 13:40). **This is a genuinely new, concrete, data-
verified hypothesis** (confirmed by reading this exact project's own
built `Image.lzma` and `Image` files byte-for-byte, not guessed) — unlike
the two hypotheses chased down earlier this same session (`gBootArgs`
corruption: real but harmless; MMU-left-on: disproven), this one has a
direct, checkable causal chain from "wrong buffer size" to "silent crash
before Linux ever runs," on every single one of the four prior attempts.
**A 5th live test is warranted once the user is present and ready** — not
yet run this pass (offline-only per this session's scope).

## Update 2026-09-08 (13): Update (12) fix retested live — identical failure a FIFTH time

Live test with the user present, using the Update (12) build (built
13:40, confirmed not stale — tested well after). Full cycle: DFU →
`checkra1n -c -k build/Pongo.bin -E` succeeded (pongoOS `05ac:4141`
confirmed live) → `load_linux.py` with the same kernel/dtbpack/initramfs/
cmdline as every prior attempt.

**Result: byte-for-byte identical to all four prior attempts.** Device
disconnected and re-enumerated as normal iOS (`05ac:12a8`); `ideviceinfo`
confirmed the exact same known-erased baseline (`BuildVersion 16H88`,
`ActivationState: Unactivated`, `BrickState: true`, same UDID). Screen
showed "Hello" again — the same Setup Assistant signature as every prior
attempt.

This is a genuinely surprising negative result: Update (12)'s finding was
not inferred, it was a direct byte-level read of this project's own
`Image.lzma` header (confirmed `0xFFFFFFFFFFFFFFFF` sentinel) and its own
built `Image` (confirmed ~24MiB, ~10x the ~2MiB the old code allocated
for it) — as solid a causal chain as this project has produced. That it
changed nothing means one of:

1. The sizing bug was real but not actually reached first — something
   earlier in `linux_prep_boot()` (ramdisk staging, FDT
   init/`fdt_open_into`, the ADT/SEPFW lookup, the display-register poke
   at the top of the function) already fails before decompression is
   ever attempted.
2. `LzmaDecode()` itself has a further issue independent of buffer
   sizing (checked `unlzma_decompress()`'s call uses `LZMA_FINISH_ANY`,
   which shouldn't require an exact size match — this was checked, not
   assumed, but not exhaustively verified against `LzmaDecode`'s full
   implementation).
3. The real blocker is genuinely earlier and lower-level than anything
   reachable by reading `linux.c`/`entry.c` C code — back to
   early-boot-assembly or a hardware/SoC-level mismatch that no amount of
   further C-level guessing will find without real hardware signal.

**Five live attempts, four independent verified-real bugs found and
fixed (two FDT-handoff issues, a decompression sizing issue found twice
under two different mechanisms, one harmless gBootArgs corruption), one
theory disproven (MMU-off), one placement confirmed correct
(`gEntryPoint` vs. the real T7000 memory map) — and the observed failure
has not changed once.** This is no longer "keep finding bugs and
retesting" territory. Per the contingency already laid out after Update
(12): **physical UART hardware access is now clearly the better use of
further effort** — continued guess-and-retest cycles against a device
that gives zero hardware-observable feedback over USB have a
demonstrated, repeated track record of not teaching us anything new, no
matter how well-verified the fix going in.

## If this is picked up again

1. ~~Live device test~~ / ~~earlycon retest~~ / ~~x0/FDT fix retest~~ /
   ~~offline FDT rebase sanity check~~ / ~~offline decompression-overflow
   investigation~~ / ~~Update (9) fix live retest~~ / ~~gBootArgs
   corruption trace~~ / ~~MMU-off-at-jump trace~~ / ~~gEntryPoint vs. real
   T7000 memory map~~ / ~~Update (12) fix live retest~~ — **all ten
   attempted. Five live attempts, all byte-for-byte identical.** Do not
   run an eleventh live attempt without either (a) real hardware signal
   from UART, or (b) a specific, checkable hypothesis for something
   earlier than kernel decompression (see Update 13's point 1) — another
   "found a plausible C-level bug, rebuilt, retested" cycle has now
   failed to change the outcome four times in a row even when the bug was
   real and well-verified each time.
2. **Physical UART hardware access is the recommended next step.** It's
   the only way left to get real hardware-observable signal (actual
   serial output or a crash program-counter/address) instead of another
   blind guess-and-retest cycle. This is a hardware-modification
   undertaking (probably wiring into the UART TX/RX/GND test points on
   the iPhone 6 logic board and reading it with a USB-serial adapter at
   the right voltage/baud) — not yet scoped, not yet authorized. Needs an
   explicit decision from the user before any board-level work is
   attempted, since it's irreversible in a way pure software attempts
   aren't.
3. If UART access is not pursued, the remaining honest options are:
   (a) the deeper C-level audit suggested in Update (13) point 1 — trace
   `linux_prep_boot()` from its very first line, verifying each step
   actually completes rather than assuming it does, ideally by adding
   diagnostic `iprintf`s at each stage boundary and checking whether
   *any* of them are visible before the crash (they wouldn't be, since
   serial is only torn down later — this could actually distinguish "how
   far did we get" if the crash is a clean hang vs image_size corruption
   before serial_teardown), or (b) accepting this tier of PLAN.md as
   genuinely unresolved for now and moving attention elsewhere.
4. Before any further live DFU cycle of any kind, re-read Updates
   (10)-(13) and the environment gotchas memory in full.

## Update 2026-09-08 (14): screen-based checkpoint instrumentation, before reaching for UART hardware

Realized there's a cheaper diagnostic than physical UART: `iprintf()`
only goes to serial (unobservable without hardware), but `screen_puts()`
writes straight to the phone's own framebuffer and is already used
elsewhere in this exact boot path (`"Booting Linux..."`, etc.) — zero
hardware modification needed, just watch the screen during the live test.

**One real constraint found while adding this:** `lowlevel_cleanup()`
(`entry.c`, called for every boot path right before the final jump)
disables the MMU. `gFramebuffer` is a VA-space alias
(`0xfb0000000`-based) that only resolves through the live page tables —
so any `screen_puts()` after the MMU goes off wouldn't just be
unreliable, it'd write to that same numeric value treated as a raw
physical address, almost certainly unmapped on this device's ~1GiB
physical map, risking a fault of its own that would contaminate the very
diagnostic this is trying to produce. So checkpoints were placed only up
to the point immediately before `lowlevel_cleanup()` runs — everything
`linux_prep_boot()` does, plus the identity-mapping setup right after it,
which covers the entire span every fix so far (Updates 6, 8, 9, 11, 12)
has targeted.

Added checkpoints (`src/modules/linux/linux.c`, `src/kernel/entry.c`),
each a distinct `screen_puts("OMERTA LP<n>: ...")`, in order:

- **LP1** — entry to `linux_prep_boot()`
- **LP2** — ramdisk staged
- **LP3** — FDT overlay applied (or `LP-FAIL` with which step)
- **LP4a** — resolved `disp` pointer address (prints the actual value)
- **LP4b** — after the `pixfmt0` register write
- **LP4** — after all display-register writes
- **LP5** — whether SEPFW was found/reserved in the ADT
- **LP6** — kernel staging buffer address + allocated size
- **LP7** — LZMA decompress return code + actual output size
- **LP7b** — resolved `image_size`
- **LP8** — FDT copied into the staging buffer
- **LP9** — `linux_prep_boot()` returning normally
- **LP-LAST** — immediately before `lowlevel_cleanup()` (MMU still on) —
  the last point any of this can possibly be reliable

**Why LP4a/4b matter and weren't considered before:** the display-register
poke (`disp[0x402c/4]` etc., resolved via `dt_get_u32_prop("disp0",
"reg")`) is untouched by any of the four fixes so far. If `"disp0"`
doesn't resolve correctly against this device's real ADT, `disp` becomes
garbage and the writes hit an arbitrary I/O register instead of the
display controller — a real, previously-unconsidered candidate for an
early silent hang. LP4a prints the resolved address so this is checkable
directly instead of assumed.

Rebuilt clean (`make all`, no errors, `build/Pongo.bin`, 2026-09-08,
see file timestamp for exact build time). **Not yet live-tested.** Next
live test should watch the screen closely and report the LAST visible
`OMERTA LP*` line when the device resets — that pinpoints the crash to
one of ~10 spans for the first time in five attempts, instead of another
guess. If `LP-LAST` is reached and the device still resets, the crash is
narrowed to `lowlevel_cleanup()` / `apply_tunables()` /
`linux_boot()`'s memcpy / the final `jump_to_image` — at that point
physical UART is genuinely the only remaining way to see further.

**Round 2, same update:** live-tested the checkpoints above and the user
reported the lines flashed by too fast to read even watching closely.
Added a ~700ms busy-wait (`omerta_diag_pause()`, a pure `get_ticks()`
poll) after every checkpoint — deliberately not this file's existing
`spin()` helper, since it calls `enable_interrupts()` on exit and
interrupts are already deliberately disabled by this point in the real
boot sequence; toggling that as a diagnostic side effect would change the
very conditions being diagnosed. Checked `wdt_enable()` first — it's dead
code (`return` before an `#if 0` body), so no live hardware watchdog to
race against the added ~8-9 seconds of total pause time. Rebuilt clean.
**Ready for the actual live retest** — watch the screen and report the
last visible line; each one should now be on-screen for a comfortable
~0.7s.

## Update 2026-09-08 (15): sixth live test — first real crash localization, plus a fifth real bug found and a fix now pending its own retest

Live test with the user present, `usbfs_memory_mb` bumped to 512,
`sudo /home/omerta/checkra1n/checkra1n -c -k build/Pongo.bin -E`
succeeded (pongoOS live), then `sudo python3 scripts/load_linux.py -k
Image.lzma -d dtbpack -r <pmbootstrap initramfs> -c "earlycon=s5l,mmio32,
0x20a0c0000 console=ttySAC0"`. All four transfer stages reported success.
Device reset to the same known-erased baseline as all five prior
attempts (`ideviceinfo`: `16H88`/`Unactivated`/`BrickState: true`, same
UDID) — **but this time, with the Update (14) round-2 pacing fix, the
user could actually read the checkpoints and reported the last one seen
was `LP4a`** (`src/modules/linux/linux.c`, prints the resolved `disp`
pointer address right before the display-register poke).

**This is the first real crash localization in six attempts.**
`dt_get_u32_prop()` (`src/kernel/dtree_getprop.c`) calls `panic()`
immediately if `"disp0"` isn't found in the ADT or `"reg"` isn't found on
it — no panic was seen, LP4a printed cleanly — so the ADT lookup itself
succeeded and `disp` is a real, ADT-sourced address. The crash is
therefore in the very next lines: the register read-modify-write
`*pixfmt0 = (*pixfmt0 & 0xF00FFFFFu) | 0x05200000u;` (or the 3
`colormatrix_*` writes right after it) — a genuinely different kind of
access than anything checked before. Every prior checkpoint on this path
(`LP1`-`LP4a`, all using `screen_puts()`) writes to `gFramebuffer`, a
plain memory buffer. This poke instead targets **display-controller MMIO
registers** at `disp + {0x402c, 0x40b4, 0x40cc, 0x40d4, 0x40dc}` — a
fundamentally riskier class of access (could easily fault, hang, or wedge
a clock-gated/security-restricted peripheral) that had gone completely
unexamined across all five prior attempts and four unrelated bug fixes.

**A fifth real, well-sourced issue, found by reading this code's own
git history:** `git log -- src/modules/linux/linux.c` shows these exact
offsets were introduced in upstream commit `baa6c5d` ("Bring back
simplefb setup"), part of a lineage that includes several
device-specific "shame list" fixes for other models (`025f4a2`, `0bf099e`,
`fcfd41f`, `d21bf7f`, `99da5d8` — 7/7 Plus, X, iPad Pro, iPhone 8/8
Plus). **This project's exact target device (N61/iPhone 6, A8) has no
commit anywhere in this file's history that specifically validates or
adjusts these register offsets for it.** The *only* place `N61` appears
in this file is `linux_fill_fdt_props()` (an unrelated function, a
framebuffer FDT `width` stride-padding quirk that N61 shares with
6S/7/8) — that says nothing about whether the DCP register layout at
these specific offsets is even the same on A8 as on whatever hardware
these offsets were tuned against. Given Update (11)'s broader finding
that this loader's Linux support was only ever validated against
A10-family hardware, a wrong register layout on A8's display-pipe IP
revision is a concrete, plausible explanation for a hard fault/hang right
here.

**Fix applied (diagnostic-first, not a guessed permanent fix):** skipped
the `pixfmt0`/`colormatrix_*` register writes entirely (replaced with
`LP4b`/`LP4` checkpoints noting they were skipped), keeping the `disp`
pointer computation and the existing `LP4a` checkpoint intact. Confirmed
safe to skip structurally: `disp` (and the 5 macros built from it) are
used nowhere else in the file — grepped to confirm. Functionally, this
poke exists purely to force the display hardware's *actual* pixel format
to match what the FDT's `simple-framebuffer` node already declares
independently (`format = "a8b8g8r8"`, set unconditionally in
`linux_fill_fdt_props()` regardless of whether this poke ran) — so
skipping it risks wrong on-screen colors under Linux at worst, not a
boot failure, and it is *not* needed for pongoOS's own `screen_puts()`
text (already proven working through `LP4a`, since that's a plain
framebuffer memory write, unrelated to this MMIO register access).
Rebuilt clean (`build/Pongo.bin`, 676,192 bytes, 2026-09-08 18:56).

**Not yet live-tested.** Next live test should watch for the last
visible `OMERTA LP*` line again:
- If it now gets past `LP4`/`LP5`/... further than `LP4a` — this
  register poke was the actual crash cause for all six attempts, a
  genuinely new and different root cause from any of the four bugs fixed
  in Updates (6)-(12) (all of which turned out to be real but not the
  actual blocker). Next step would be to either find/derive the correct
  A8-specific register offsets, or just leave this poke permanently
  skipped and accept cosmetic color risk in exchange for a booting
  console.
- If it crashes again at the same point (immediately after the new
  `LP4a`, i.e. before even reaching the new "SKIPPED" `LP4b`/`LP4`
  lines) — that would be a very strange result implying the crash isn't
  in the poke at all, and reopens the question of what's really
  happening around the `disp`/ADT lookup itself despite no panic being
  observed.
- If it proceeds further but still resets before `LP-LAST` — same
  checkpoint-narrowing approach continues into `LP5`
  (SEPFW/ADT reservation check), `LP6`-`LP7b` (kernel decompression,
  already the subject of Updates 9/12's fixes), or `LP8`/`LP9`
  (FDT copy / normal return).

**Seventh live attempt (same session, same build): inconclusive — user
missed reading the last visible line.** Same DFU/checkra1n/load_linux.py
sequence against the Update (15) build (poke skipped); device reset to
the same known-erased baseline again (`ideviceinfo` confirmed, USB
device number changed from prior enumeration confirming a fresh
cycle happened), but the checkpoint line wasn't caught in time even at
~0.7s/line. **No new data from this attempt — do not count it as
evidence either way for the Update (15) fix.** Paused further live
cycles here by user choice rather than keep guessing.

**Recommendation for the next live attempt:** don't rely on reading the
screen live — **film the phone's screen with a second camera during the
boot sequence**, then review the recording frame-by-frame (or send a
photo/frame of the last visible line) afterward. This removes the
timing-pressure failure mode entirely and should be the standard method
from here on, not just a one-off suggestion. The Update (15) build
(`build/Pongo.bin`, 676,192 bytes, 2026-09-08 18:56, display-register
poke skipped) is still the correct one to test next — no code changes
are needed before the next attempt, just a better capture method.

## Update 2026-09-08 (16): independent offline verification of LP4a via the real N61 firmware (blacktop/ipsw)

Offline-only, no device touched. The user installed `blacktop/ipsw`
(confirmed on `PATH` via snap, v3.1.713) and pointed out
`~/Downloads/iPhone_4.7_12.5.8_16H88_Restore.ipsw` is sitting on disk —
this is the **exact same build** as the real target device (iPhone7,2,
16H88), not just a same-generation reference.

Used it to extract and decode the real DeviceTree
(`ipsw extract --dtree`, `ipsw dtree`) and cross-check the `disp0` node
against what `linux.c`'s `dt_get_u32_prop("disp0", "reg")` call (the
LP4a checkpoint) computes at runtime. Confirmed:

- Board Config `N61AP`, `iPhone7,2`, `iPhone 6` — exact match to the
  physical device, not inferred.
- The real `disp0` node's `reg` property is 5 address/size tuples, the
  first being `addr=0x6200000 sz=0x100000`. `dt_get_u32_prop()`
  (`dtree_getprop.c:29-38`) just `memcpy`s the first 4 bytes of the
  prop into a `uint32_t` — i.e. it returns exactly `0x6200000`, the
  correct base of that first tuple, not garbage from misreading a
  wider/differently-shaped property.
- This **independently confirms Update (15)'s reasoning was right**:
  LP4a's `disp` pointer (`0x6200000 + gIOBase`) is a real, correctly
  computed MMIO address for this exact device — the crash sequence for
  all six prior identical live failures genuinely was downstream of a
  legitimate address, not an ADT-resolution bug. No code change follows
  from this (Update 15 already skips the poke); it's confirmation the
  skip targets the right thing rather than a shot in the dark.

Also extracted the matching `iBoot.n61.RELEASE.im4p` for future use
(unopened this pass — the `disp0` DeviceTree check answered the
immediate question). If the Update (15) skip build's next live test
still fails before reaching `LP-LAST`, a good next ipsw-assisted step is
disassembling this iBoot to see Apple's own T7000 display bring-up
sequence (e.g. whether `power-gates`/`clock-gates` must be poked before
`pixfmt0`/`colormatrix_*` are touched at all) — `ipsw fw iboot` on the
extracted im4p, or `ipsw img4` first if it turns out to need
IM4P-unwrapping. Both files are cached at `~/omerta-ipsw-work/` for
reuse without re-extracting from the 3GB+ IPSW.

**Status unchanged: still waiting on the next live test of the Update
(15) build with filmed screen capture** — this update adds confidence,
not a new blocker or a new fix.

## Update 2026-09-13 (17/18): FDT collision guard added, found likely inert; `LP3a` added to confirm with data

Between the last session and this one, `linux_dtree_overlay()`
(`src/modules/linux/linux.c`) picked up a defensive fix: the unconditional
`fdt_add_subnode(fdt, node, "memory@800000000")` under `/reserved-memory`
(only reached when `gBootArgs->physBase > 0x800000000`) collides with
`t7000.dtsi`'s own `hacky_reserved_mem: memory@800000000` node of the same
name — the old code treated the resulting error as fatal. Fixed by
checking `fdt_subnode_offset()` first and skipping the add if it's
already there.

Re-reading the two live attempts from the 09-08 session showed this
branch was almost certainly never entered on the real device in the
first place (both ran the old, unconditional code and returned success),
implying `gBootArgs->physBase` equals exactly `0x800000000` on this
hardware. Added `LP3a` to print `physBase` directly and confirm this
with data rather than inference. Rebuilt clean, not live-tested yet at
the time.

## Update 2026-09-13 (19): live Attempt #9 shows the freeze is EARLIER than every prior session assumed

Live-tested the Update 17/18 build with the user present and watching
the screen closely. **Confirmed directly (not inferred): `"Booting
Linux..."` was the literal last thing on screen — `OMERTA LP-LAST`
(which has a multi-second busy-wait specifically so it can't be missed)
never appeared before the reset.**

Re-reading the 09-08 session's own logs found that neither of its two
live attempts had actually *confirmed* `LP-LAST` legible either — both
were inferred from indirect signals (a blurry photo/video, and a
white-flash test result), never read directly. So this project has
never once had a confirmed sighting of `LP-LAST` — Attempt #9 is the
first time its *absence* was confirmed rather than assumed.

Traced the code and found a genuinely new, previously-unexamined gap:
`pongo_entry_cached()` (the function that runs the whole shell,
`linux_prep_boot()`, and prints `"Booting Linux..."`) *returns* into
`pongo_entry()`, which then runs three more steps that have never been
checkpointed by anything — `lowlevel_set_identity()`,
`rebase_pc(-gPongoSlide)`, and a second `set_exception_stack_core0()` —
before ever reaching `LP-LAST`. Added four new checkpoints bisecting
this span (`LP9c`-`LP9f`), same busy-wait pattern as `LP-LAST` for
legibility. Rebuilt clean, not live-tested yet at the time.

## Update 2026-09-13 (20): deskewed Attempt #9 photo, plus a strong new hypothesis — the diagnostic itself may be the cause

The single Attempt #9 photo turned out to be salvageable: rotating it
~35° (the phone was held at a steep angle to the camera) and cropping
tight made every line legible. Confirmed the photo matches what the
user reported live — `Booting Linux...` is the last line, nothing past
it — and that this was the *old* build (Update 19's `LP9c`-`LP9f`
checkpoints didn't exist yet in the binary this attempt actually ran).

While adding the Update 19 checkpoints, found a strong new hypothesis:
the three newly-instrumented steps are shared with the ordinary XNU
boot path checkra1n uses on every device — well-exercised, unlikely to
hide a new bug. But the very next line, `gFramebuffer =
gBootArgs->Video.v_baseAddr` immediately followed by `LP-LAST`'s
`screen_puts()`, is different: **XNU's boot path never does a
`screen_puts()` after that reassignment** (it jumps straight to
`exit_to_el1_image()`), so this project's own `LP-LAST` diagnostic is
the first and only code ever to call `screen_puts()` through that
post-identity-map framebuffer pointer. If `gBootArgs->Video.v_baseAddr`
falls outside the `[0x800000000+g_phys_off, +ram_phys_size)` window
`lowlevel_set_identity()` just mapped, using it as a VA would silently
fault — meaning **the diagnostic itself could be the actual cause of
the freeze**, not a real Linux-boot bug.

Added `LP9g`, printed via the OLD (proven-good) `gFramebuffer` *before*
the risky reassignment — reports `gBootArgs->Video.v_baseAddr`, the
identity-mapped range, and an explicit `IN-RANGE`/`OUT-OF-RANGE!!`
verdict, so this gets checked with data instead of guessed. Rebuilt
clean (`build/Pongo.bin`, 676,192 bytes, 2026-09-13 17:25), no errors,
no new warnings.

**Not yet live-tested.** Next live attempt (#10): report the
`LP9c`-`LP9g` lines verbatim — the `LP9g` verdict matters most. If
`OUT-OF-RANGE!!`, that's a confirmed root cause (fix: skip the
Linux-path framebuffer reassignment, or move `LP-LAST` before it). If
`IN-RANGE`, the freeze is genuinely in `lowlevel_cleanup()`/
`apply_tunables()`/`linux_boot()`/the final jump, same as always
assumed. Full detail (including the exact photo-reading process) is in
`phase3/kernel/pongo-linux-src/TESTLOG.md` (local-only — that directory
is gitignored since it's a vendored upstream fork).

## Update 2026-09-13 (21): Attempt #10 — a real panic captured on camera, root cause found and fixed

Ran the Update 20 (`LP9g`) build live. Two screen-recording videos came
back unreadable (phone held too close for the webcam to focus — genuine
optical defocus, not motion blur). A still photo taken afterward,
though, caught something this project has never seen before in ~10 live
attempts across two sessions: **an actual panic screen**, not another
silent black-screen reset.

After correcting for the photo's EXIF rotation, the panic read: `panic:
caught sync exception with interrupts masked`, `crashed process:
kernel`, a register dump, and — critically — `ELR: 0x0000000100 01ae18`
(`image_base + 0x1ae18`). Resolving that address against the actual
built binary's own symbol table (`llvm-nm-21 build/Pongo`, not guessed)
puts it at `.Lcopy16 + 0x8`, **inside `_memcpy` itself**. (The fp/lr
backtrace in the same panic was stack garbage — resolved to unrelated
newlib internals with no coherent call chain — so only the ELR, the
actual faulting PC, was trustworthy here.)

**Root cause, confirmed from code**: `linux_boot()`
(`src/modules/linux/linux.c`) calls `memcpy(gEntryPoint, gLinuxStage,
gLinuxStageSize)`, and its own existing comment already documented that
this runs *after* `lowlevel_cleanup()` disables the MMU. Per the ARMv8
architecture, with the MMU off every data access is treated as
Device-nGnRnE memory, which explicitly forbids Advanced SIMD/NEON
load-store instructions — and this codebase's `memcpy` is a `clang -O3`
auto-vectorized generic libc routine that copies in 16-byte NEON chunks
(hence the `.Lcopy16` label). That's a guaranteed data abort on the
very first vector access, unconditionally, on every call regardless of
source/dest/size — which is exactly why every one of the ~10 live
attempts across both sessions died at this identical point no matter
which of the four earlier real bugs (x0/FDT handoff ×2, decompression
heap overflow, LZMA sentinel) got fixed. None of them ever mattered:
execution never got past this memcpy.

**Fix**: replaced that `memcpy()` with `smemcpy128()`
(`src/boot/entry.S`) — a hand-written copy routine that already exists
in this exact codebase for exactly this situation (`trampoline_entry` in
`stage3.c` uses it for a copy that also has to happen before the
MMU/EL1 environment is set up), using only plain-X-register
`ldp`/`stp`, which Device memory does permit. Rebuilt clean
(`build/Pongo.bin`, 676,192 bytes, 2026-09-13 17:48).

**Not yet live-tested — this is the first fix in the whole project
backed by an actual captured panic and a symbol-resolved fault address,
rather than inference from a silent reset.** Next live attempt: if
this is right, the failure signature should finally change — either
Linux produces visible output, or it fails further in, which would
itself be real progress for the first time in 10 attempts. Full detail
in `phase3/kernel/pongo-linux-src/TESTLOG.md` (local-only, gitignored).

## Update 2026-09-13 (22): Attempt #11 — Update 21's fix wasn't actually tested yet; a bug in the diagnostic itself, found and fixed

Live-tested the Update 21 (`smemcpy128`) build. A photo caught another
double panic, same structural shape as Attempt #10's. Good news first:
`LP9c`-`LP9f` (Update 19) all printed successfully, and `LP3a` read
exactly `physBase=800000000` as Update 17/18 predicted — real,
independently-confirmed progress.

But `LP9g` (Update 20) never printed at all — the crash happened
*inside* that diagnostic block, meaning `linux_boot()`'s fixed `memcpy`
call was never actually reached. The first panic's `FAR` sat only ~20
bytes from `SP`, pointing at a stack-proximate fault.
`set_exception_stack_core0()` does `msr spsel, #1`, switching all
subsequent code onto the small, fixed `_exception_stack` — `LP9c`-`LP9f`'s
plain `screen_puts()` never stressed it, but `LP9g`'s `siprintf()` call
(variadic args, its own internal calls) was apparently enough to run
past the end of it. A different bug class entirely from Update 21's
(stack sizing, not NEON-on-Device-memory) and introduced by this
project's own diagnostic code, not the real boot path.

**Fix**: removed the `LP9g` block. Its question is now secondary to
Update 21's confirmed fix, and re-adding an equivalent check without
`siprintf` isn't worth risking the same class of bug again right before
that fix finally gets tested. Rebuilt clean (`build/Pongo.bin`,
676,192 bytes, 2026-09-13 18:25).

**Not yet live-tested — this will be the first attempt to actually
reach the Update 21 fix with nothing else in the way.** Full detail in
`phase3/kernel/pongo-linux-src/TESTLOG.md` (local-only, gitignored).
