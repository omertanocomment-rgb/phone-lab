# OMERTA iOS — Staged Plan (iPhone 6 / A8 / s8000)

## Why staged

`checkra1n` is a boot/jailbreak/bootstrap tool, not an IPSW installer — there is no `--export`/`--install-ipsw` flag because a custom firmware image and a jailbreak bootstrap are architecturally different things. The existing `OMERTA-iOS-Phase1-final.zip` (Theos tweak source, checkra1n jailbreak notes, Odyssey headless debug notes) is real Phase 1 work but it's a userspace jailbreak/tweak layer, not a bootable OS. This plan gets from "jailbreak + tweaks" to "iPhone 6 boots into an OMERTA-branded pre-boot / status environment" without ever mislabeling an intermediate artifact as a finished firmware image.

## Phase 1 — Jailbreak + tweak layer (existing, needs merge)

```
iPhone 6 → checkra1n → jailbroken iOS → Theos/tweaks → OMERTA components
```

Contents per the uploaded ZIP:
- `OMERTA-iOS-PLAN.md`
- `OMERTAiOS-tweak/` — Objective-C/Theos tweak source
- `toolchain/01-jailbreak-iphone6-checkra1n.md`
- `toolchain/02-theos-bootstrap-mint.sh`
- `toolchain/03-odyssey-bootstrap-and-headless-debug.md`

**Status: pending merge.** This scaffold doesn't have the ZIP in-session — drop its contents into `phase1/` (see `phase1/README.md`) and it slots straight into this tree.

## Phase 2 — pongoOS boot environment (this scaffold, built)

```
iPhone 6 → DFU → checkm8/checkra1n bootstrap → pongoOS (+ OMERTA module) → OMERTA boot status → bootx into stock iOS
```

pongoOS is a **pre-boot execution environment**, not a replacement iOS. checkra1n's `-k` flag hands it a Pongo binary to run before the phone continues to XNU (or stays in the Pongo shell). This is the safest layer to build on: it's fully RAM-resident and testable without touching the phone's filesystem or restore state.

Steps (see `phase2/README.md` for exact commands):

1. Confirm hardware: iPhone 6 = A8 = platform `s8000` (checkm8-vulnerable, in-scope for checkra1n/pongoOS).
2. Verify DFU communication — `tools/dfu/detect.sh` (uses `irecovery`/`ideviceinfo`, which your `ios-tooling-builder` work already produced for 32-bit Android/Termux).
3. Build upstream pongoOS (`phase2/pongo-src/` submodule, pulled at build time) via the CI workflow — produces `Pongo.bin` and `PongoConsolidated.bin`.
4. Build the OMERTA Pongo module (`phase2/modules/omerta_boot/`) — a loadable module using pongoOS's real module ABI (`module_entry()`, `command_register()`, `preboot_hook`), not invented.
5. Test booting Pongo standalone via `checkra1n -k Pongo.bin` — confirms DFU/checkm8/Pongo chain works before touching anything else.
6. Load the OMERTA module over USB (`phase2/tools/omerta_load.py`) and run the `omerta` shell command — this is the "OMERTA boot/status screen," text/serial-console for this phase.
7. Wire the module's `preboot_hook` so the OMERTA banner prints automatically on every boot, then falls through to normal `bootx`.
8. Only after 1–7 are solid: investigate persistent OMERTA state (something the Pongo module can read/write, e.g. an NVRAM-ish flag) — still phase2, but the last, riskiest item.

## Phase 3 — Persistent userspace/OS work (not started, scoped only)

```
Custom source → iOS-compatible system/kernel/rootfs → custom boot chain → device-specific packaging → DFU/bootloader install
```

This is the "genuine custom OS" tier. On an iPhone 6, checkm8 gives low-level control, but Apple's normal firmware signing/restore chain still applies to anything claiming to be a real IPSW — you cannot hand checkra1n an arbitrary modified IPSW and have it accepted through the normal restore path. Real options here, roughly in order of realism:

- Extend the phase1 jailbreak/tweak layer so more of "OMERTA" lives as a Theos tweak + LaunchDaemon that starts automatically post-jailbreak (persistent across reboots as long as the jailbreak is re-applied, which is the normal checkra1n semi-tethered model).
- Use the phase2 Pongo module to `bootx` into a **patched ramdisk** (this is what `boot-checkra1n.py` upstream demonstrates — pushing a ramdisk over USB alongside the Pongo binary) for a custom recovery-style environment, without touching the installed iOS at all.
- A genuine alternate kernel/rootfs boot (Linux-on-iPhone style, which pongoOS's own `src/modules/linux/` driver support hints was explored upstream) is a multi-month research project on its own and is out of scope until phase2 is proven.

Nothing in phase3 is built yet. It's scoped here so phase2 decisions (module ABI, boot hook structure) don't paint us into a corner.

## Hardware notes

- iPhone 6 SoC: Apple A8, platform string `s8000` in pongoOS (`src/drivers/plat/s8000.c` upstream).
- checkm8 (`SecureROM`) is a permanent hardware-level DFU exploit on A7–A11 devices — cannot be patched by Apple via software update, which is why this whole chain is durable across iOS versions on this specific phone.
- Everything phase2 does is **RAM-only / tethered**: a reboot returns the phone to stock behavior until you re-run the DFU → checkra1n → Pongo → module chain. That's expected and matches how checkra1n itself works, not a bug in this project.

## Source of truth for the pongoOS build details in this scaffold

Verified directly against the upstream `checkra1n/PongoOS` repo (Makefile, `example/testmodule/`, `example/include/pongo.h`, `src/shell/command.c`, `scripts/module_load.py`, `scripts/boot-checkra1n.py`) rather than assumed — see `phase2/README.md` for the exact API used.
