# Phase 2 — pongoOS boot environment

Everything here is checked against the real upstream `checkra1n/PongoOS` source (Makefile, `example/testmodule/`, `example/include/pongo.h`, `src/shell/command.c`, `scripts/module_load.py`, `scripts/boot-checkra1n.py`) — not guessed at.

**Same `checkra1n` binary as phase1, different flag.** `../phase1/toolchain/01-jailbreak-iphone6-checkra1n.md` already has you running `sudo ./checkra1n` with no `-k` flag to fully jailbreak the phone (checkra1n's default mode: exploit + patch + boot straight to a jailbroken iOS). Everything below uses that exact same binary (checkra1n 0.12.4 — matches the `CHECKRA1N_VERSION` this pongoOS build embeds) with `-k <file>` added, which instead boots the phone into *your* Pongo binary and stops there — no jailbreak, no iOS boot, unless you explicitly send `bootx` afterward. You don't need a second install; whatever `~/checkra1n/checkra1n` phase1 already has you using works here too. Don't run both modes at once — reboot/re-DFU between a `-k` session and a normal jailbreak session.

## Layout

```
phase2/
├── modules/omerta_boot/   OMERTA's loadable pongoOS module (source, real module ABI)
│   ├── main.c
│   └── Makefile
├── tools/
│   ├── omerta_load.py     pushes the built module over USB into a running Pongo shell
│   └── boot_omerta.sh     one-shot: checkra1n -k ... && wait for USB && push module
├── pongo-src/             NOT checked in -- cloned fresh by CI (or by you locally)
└── build/                 local scratch, gitignored
```

## Option A: build in CI (recommended)

Push this repo to GitHub and either let `.github/workflows/build-pongo.yml` run on a push touching `phase2/**`, or trigger it manually from the Actions tab (`workflow_dispatch`, optionally pinning a specific `checkra1n/PongoOS` git ref). Download the `pongo-build` artifact when it finishes — it contains:

- `Pongo.bin` — bare-metal Pongo binary, no KPF
- `PongoConsolidated.bin` — Pongo + kernel patchfinder combined
- `checkra1n-kpf-pongo` — the KPF module on its own
- `omerta_boot` — the OMERTA module, built against that same pongoOS checkout
- `BUILD_INFO.txt` — exact upstream commit hash it was built from

Put these in `../output/`.

## Option B: build locally (Linux host, not Termux)

**This sequence was run end-to-end locally (Ubuntu 24.04, clang 18.1.3) and produced real `Pongo.bin` / `PongoConsolidated.bin` / `checkra1n-kpf-pongo` / `omerta_boot` binaries** — not copied from the upstream README and assumed to work. A first attempt at wiring the same steps into GitHub Actions CI surfaced one more issue this local run's specific machine state didn't hit (a stale `llvm-ar` already on `PATH` from something installed earlier) — folded in below as issue 4, so this list is now more complete than the original local run was. Four things need fixing beyond the README's own instructions, because modern Ubuntu/clang is stricter than whatever the pongoOS team builds with; the CI workflow applies the same four fixes:

```bash
# 1. ld64's Debian package depends on libssl1.1, which Ubuntu 24.04
#    (Noble) no longer ships. Pull it from the Focal security archive first.
curl -fsSL -o /tmp/libssl1.1.deb "http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb"
sudo dpkg -i /tmp/libssl1.1.deb

echo 'deb https://assets.checkra.in/debian /' | sudo tee /etc/apt/sources.list.d/checkra1n.list
curl -fsSL https://assets.checkra.in/debian/archive.key | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y ld64 cctools-strip clang llvm-18 git xxd   # xxd is needed by the Makefile's own PongoConsolidated.bin step

# 4. pongoOS's newlib cross-build hardcodes AR=llvm-ar / RANLIB=llvm-ranlib
#    (unversioned). Ubuntu's llvm-18 package only installs versioned
#    binaries (llvm-ar-18, llvm-ranlib-18) and registers no
#    update-alternatives entry to bridge them -- confirmed empirically
#    against a real apt system, not assumed. Symlink them yourself:
sudo ln -sf "$(command -v llvm-ar-18)" /usr/local/bin/llvm-ar
sudo ln -sf "$(command -v llvm-ranlib-18)" /usr/local/bin/llvm-ranlib

git clone --recurse-submodules https://github.com/checkra1n/PongoOS.git phase2/pongo-src
cd phase2/pongo-src

# 2. src/kernel/task.c calls va_start()/va_end() without including
#    <stdarg.h>. Older clang treated these as builtins regardless;
#    clang 18 does not, and the link fails on undefined _va_start.
#    One-line upstream bug, not ours -- patch it in:
grep -q '#include <stdarg.h>' src/kernel/task.c || \
  sed -i '/#include <stdlib.h>/a #include <stdarg.h>' src/kernel/task.c

# 3. clang 18 hard-errors on implicit-function-declaration and on a
#    couple of set-but-unused locals in pongoOS's own mm.c/kpf main.c
#    that -Werror then also catches. -flto means ld64 needs libLTO.so
#    to process the bitcode objects clang emits -- point it at the
#    apt-installed LLVM 18's copy explicitly.
EMBEDDED_CC=clang \
EMBEDDED_LDFLAGS="-fuse-ld=/usr/bin/ld64 -Wl,-lto_library,/usr/lib/llvm-18/lib/libLTO.so.18.1" \
STRIP=cctools-strip \
EMBEDDED_CFLAGS="-Wno-error -Wno-implicit-function-declaration" \
make all
cd -

cd phase2/modules/omerta_boot
EMBEDDED_CC=clang \
EMBEDDED_LDFLAGS="-fuse-ld=/usr/bin/ld64 -Wl,-lto_library,/usr/lib/llvm-18/lib/libLTO.so.18.1" \
STRIP=cctools-strip \
EMBEDDED_CFLAGS="-Wno-error -Wno-implicit-function-declaration" \
PONGO_SRC=../../pongo-src \
make all
cd -
```

Confirms as: `build/Pongo.bin` and `build/PongoConsolidated.bin` as raw bare-metal arm64 binaries, `build/checkra1n-kpf-pongo` and `phase2/modules/omerta_boot/build/omerta_boot` as `Mach-O 64-bit arm64 kext bundle`s (`file` on the output binary confirms this). `strings` on `omerta_boot` shows the real registered command/strings (`omerta`, `show the OMERTA iOS boot status banner`, `omerta_boot`, the banner text) baked into the binary, confirming the module ABI in `main.c` actually compiles and links against real pongoOS/newlib headers, not just plausible-looking C.

If you hit a different clang version's own set of warnings-turned-errors on some other distro, the pattern is the same: `EMBEDDED_CFLAGS="-Wno-error -Wno-<specific-warning>"` widens without ever touching pongoOS's own source, except the one genuine upstream bug (missing `#include <stdarg.h>`) which has no such flag-only fix.

This is an x86_64/arm64 Linux (or macOS) host thing, not a Termux/on-device thing — same reasoning as why `omerta-bootloader-toolkit`'s APK compilation moved to GitHub Actions rather than fighting `dl.google.com` from the sandbox. Termux is fine for driving the *device side* (DFU detection, `irecovery`, running `omerta_load.py` once binaries exist) — just not for the pongoOS cross-compile itself, since `ld64`/`cctools-strip` aren't Termux packages.

## Running it against the iPhone 6

1. Confirm the phone is in DFU: `../tools/dfu/detect.sh` (expects `CPID:8000` for A8/iPhone 6).
2. One-shot: `./tools/boot_omerta.sh ../output/Pongo.bin modules/omerta_boot/build/omerta_boot`
   — this runs `checkra1n -k Pongo.bin`, waits for the pongoOS USB device (`05ac:4141`) to enumerate, then pushes and loads the module automatically.
3. Or manually, step by step:
   ```bash
   checkra1n -k ../output/Pongo.bin &          # boots to bare Pongo shell
   python3 tools/omerta_load.py modules/omerta_boot/build/omerta_boot
   ```
4. Attach to the Pongo shell over serial/USB (upstream's `scripts/pongoterm.c` is the reference client) and run:
   ```
   pongoOS> omerta
   ```
   You should see the OMERTA boot status banner (device type, boot_args revision, tick count). **See "Known issues" below** — reading the shell's text response back over the USB control-transfer protocol (as opposed to a real UART/serial connection) did not work in real-hardware testing, even using upstream's own unmodified reference scripts.
5. To also test the auto-print-on-boot path, once the module is loaded run `bootx` — the module's `preboot_hook` chain prints the banner once, then hands off to whatever was already hooked (KPF etc.) before continuing to XNU.

## The module ABI, briefly

`example/testmodule/main.c` upstream is the canonical reference: a module exports `module_entry()` (called once on load), a `module_name` string, and a `pongo_exports[]` table (empty here — nothing else links against `omerta_boot` yet). Inside `module_entry()` we do exactly what upstream's example does: save the existing `preboot_hook`, install our own that chains to it, and call `command_register(name, description, callback)` to add a shell command. `omerta_boot/main.c` follows this pattern with real OMERTA content instead of the "Hello world" stub.

## What this is not (yet)

- No framebuffer/graphical splash — pongoOS has an `fb.c` driver upstream, but wiring a graphical OMERTA logo through it is real additional work, scoped as a phase3 candidate, not pretended to exist here.
- No persistence — every boot means re-running DFU → checkra1n → module push. This is inherent to checkm8-class tethered tooling (`checkra1n` itself has the exact same property), not a shortcut we're missing.
- No custom kernel/ramdisk yet — upstream's `scripts/boot-checkra1n.py` shows the pattern for pushing a ramdisk after Pongo (`modload` then `ramdisk` then `bootx`), which is the natural next phase2 step if you want OMERTA to influence what XNU actually boots into, not just what prints before it.

## Known issues (from real hardware testing)

**checkm8 exploit, Pongo boot, and `omerta_boot` module load are all confirmed working end-to-end on a real iPhone 6** — repeated, reliable `05ac:4141` pongoOS USB enumeration after `checkra1n -k`, and `omerta_load.py` reports a clean push every time with no error from the device.

**Reading the shell's text output back over USB does not currently work in this setup.** The write direction (`ctrl_transfer(0x21, 3, 0, 0, "<cmd>\n")` — injecting a command into stdin) works fine and the device stays alive. But reading stdout back (`ctrl_transfer(0xa1, 1, 0, 0, 512)` — the same request `example`/`src/shell/usbloader.c`'s `ep0_device_request()` and upstream's own `scripts/fetch_stdout.py` use) reliably times out (`USBTimeoutError: [Errno 110] Operation timed out`) on a Linux host with `pyusb`/`libusb1`, using upstream's *unmodified* reference script — not something specific to this project's own tooling. In earlier attempts, repeatedly polling this same request in a tight loop crashed the device outright (USB disconnect, phone resets to Recovery Mode); a single one-shot read (matching how upstream's scripts are meant to be run — as separate one-off invocations, not a polling loop) times out cleanly without crashing the device.

Not yet root-caused. Candidates worth checking before spending more device cycles on it: a real UART/serial connection instead of this USB control-transfer protocol (this project has no serial cable/adapter set up yet); a `libusb`/kernel version mismatch between what this host runs and whatever pongoOS's own developers test against; or a genuine short-packet-handling bug in pongoOS's minimal EP0 stack that only surfaces with certain USB controllers/drivers. `usbmon`/Wireshark packet capture during a read attempt is the logical next debugging step, not attempted yet.

**Practical implication:** the `omerta` command and the `preboot_hook` banner-on-`bootx` path are both believed to work (the module loads, registers the command, and hooks correctly per its own source), but this has not been *visually or textually confirmed* on this hardware — only confirmed via the absence of any load-time error and successful re-enumeration.
