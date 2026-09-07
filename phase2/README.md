# Phase 2 — pongoOS boot environment

Everything here is checked against the real upstream `checkra1n/PongoOS` source (Makefile, `example/testmodule/`, `example/include/pongo.h`, `src/shell/command.c`, `scripts/module_load.py`, `scripts/boot-checkra1n.py`) — not guessed at.

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

pongoOS needs `ld64` and `cctools-strip`, which checkra1n ships as Debian packages:

```bash
echo 'deb https://assets.checkra.in/debian /' | sudo tee /etc/apt/sources.list.d/checkra1n.list
curl -fsSL https://assets.checkra.in/debian/archive.key | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y ld64 cctools-strip clang git

git clone --recurse-submodules https://github.com/checkra1n/PongoOS.git phase2/pongo-src
cd phase2/pongo-src
EMBEDDED_CC=clang EMBEDDED_LDFLAGS=-fuse-ld=/usr/bin/ld64 STRIP=cctools-strip make all
cd -

cd phase2/modules/omerta_boot
EMBEDDED_CC=clang EMBEDDED_LDFLAGS=-fuse-ld=/usr/bin/ld64 STRIP=cctools-strip make all
cd -
```

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
   You should see the OMERTA boot status banner (device type, boot_args revision, tick count).
5. To also test the auto-print-on-boot path, once the module is loaded run `bootx` — the module's `preboot_hook` chain prints the banner once, then hands off to whatever was already hooked (KPF etc.) before continuing to XNU.

## The module ABI, briefly

`example/testmodule/main.c` upstream is the canonical reference: a module exports `module_entry()` (called once on load), a `module_name` string, and a `pongo_exports[]` table (empty here — nothing else links against `omerta_boot` yet). Inside `module_entry()` we do exactly what upstream's example does: save the existing `preboot_hook`, install our own that chains to it, and call `command_register(name, description, callback)` to add a shell command. `omerta_boot/main.c` follows this pattern with real OMERTA content instead of the "Hello world" stub.

## What this is not (yet)

- No framebuffer/graphical splash — pongoOS has an `fb.c` driver upstream, but wiring a graphical OMERTA logo through it is real additional work, scoped as a phase3 candidate, not pretended to exist here.
- No persistence — every boot means re-running DFU → checkra1n → module push. This is inherent to checkm8-class tethered tooling (`checkra1n` itself has the exact same property), not a shortcut we're missing.
- No custom kernel/ramdisk yet — upstream's `scripts/boot-checkra1n.py` shows the pattern for pushing a ramdisk after Pongo (`modload` then `ramdisk` then `bootx`), which is the natural next phase2 step if you want OMERTA to influence what XNU actually boots into, not just what prints before it.
