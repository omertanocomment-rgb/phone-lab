# OMERTA iOS — Staged Plan (iPhone 6 / A8 / s8000)

## Why staged

`checkra1n` is a boot/jailbreak/bootstrap tool, not an IPSW installer — there is no `--export`/`--install-ipsw` flag because a custom firmware image and a jailbreak bootstrap are architecturally different things. The existing `OMERTA-iOS-Phase1-final.zip` (Theos tweak source, checkra1n jailbreak notes, Odyssey headless debug notes) is real Phase 1 work but it's a userspace jailbreak/tweak layer, not a bootable OS. This plan gets from "jailbreak + tweaks" to "iPhone 6 boots into an OMERTA-branded pre-boot / status environment" without ever mislabeling an intermediate artifact as a finished firmware image.

## Phase 1 — Jailbreak + tweak layer (merged, real-device-tested)

```
iPhone 6 → checkra1n → jailbroken iOS → Theos/tweaks → OMERTA components
```

Contents, merged from `OMERTA-iOS-Phase1-final.zip`:
- `OMERTA-iOS-PLAN.md` — its own 5-phase roadmap for the tweak (owner-lock → duress PIN → Safe Mode → hidden control hub → package), separate from this file's Phase 1/2/3
- `OMERTAiOS-tweak/` — Objective-C/Theos tweak source, plus a built, tested `.deb`
- `toolchain/01-jailbreak-iphone6-checkra1n.md`
- `toolchain/02-theos-bootstrap-mint.sh`
- `toolchain/03-odyssey-bootstrap-and-headless-debug.md`
- `install-omerta-ios.sh` — end-to-end scripted install with recovery for the known dpkg/apt bugs

**Status: code-complete and verified over SSH — visual confirmation blocked.** The tweak installs cleanly, its SpringBoard hook fires, and its Keychain PIN write is independently confirmed via syslog. What's not yet confirmed is the lock overlay actually rendering, because the test unit is iCloud Activation Locked from a previous owner (unrelated to the tweak — see `phase1/toolchain/03-odyssey-bootstrap-and-headless-debug.md` section 5). No software workaround exists or should be attempted for Activation Lock. Per the plan's own stated rule, its internal Phase 2 (duress PIN) does not start until this is resolved for real, either on this unit through a legitimate path or on a second clean device.

## Phase 2 — pongoOS boot environment (this scaffold, built)

```
iPhone 6 → DFU → checkm8/checkra1n bootstrap → pongoOS (+ OMERTA module) → OMERTA boot status → bootx into stock iOS
```

pongoOS is a **pre-boot execution environment**, not a replacement iOS. checkra1n's `-k` flag hands it a Pongo binary to run before the phone continues to XNU (or stays in the Pongo shell). This is the safest layer to build on: it's fully RAM-resident and testable without touching the phone's filesystem or restore state.

Steps (see `phase2/README.md` for exact commands):

1. ✅ Confirm hardware: iPhone 6 = A8 = platform `s8000` (checkm8-vulnerable, in-scope for checkra1n/pongoOS). Confirmed via `ideviceinfo` (`ProductType: iPhone7,2`, `HardwareModel: N61AP`) and independently via 3uTools.
2. ✅ Verify DFU communication — `tools/dfu/detect.sh` (uses `irecovery`/`ideviceinfo`).
3. ✅ Build upstream pongoOS via the CI workflow — produces `Pongo.bin` and `PongoConsolidated.bin`. Real GitHub Actions run, artifact downloaded and verified (`file` confirms genuine Mach-O/bare-metal arm64 binaries).
4. ✅ Build the OMERTA Pongo module (`phase2/modules/omerta_boot/`) — real module ABI (`module_entry()`, `command_register()`, `preboot_hook`).
5. ✅ Test booting Pongo standalone via `checkra1n -k Pongo.bin` — confirmed repeatedly on real hardware (`05ac:4141` USB enumeration every time).
6. ✅ Load the OMERTA module over USB and run the `omerta` shell command. **Visually confirmed on the phone's own screen** — pongoOS's console writes to the live framebuffer (`screen_putc()` in `fb.c`, reading `gBootArgs->Video`), not just USB, so the banner rendered directly on-device.
7. ✅ Wire the module's `preboot_hook` so the OMERTA banner prints automatically on every boot, then falls through to normal `bootx`. Confirmed: running `bootx` re-printed the banner via the hook chain and the boot continued through to iOS (device reachable again afterward via `ideviceinfo`).
8. Only after 1–7 are solid: investigate persistent OMERTA state (something the Pongo module can read/write, e.g. an NVRAM-ish flag) — still phase2, but the last, riskiest item. **Not started** — the only remaining open phase2 item.

All of 1–7 confirmed on a real iPhone 6 the night of 2026-09-07/08. See `phase2/README.md`'s "Known issues" section for one still-open side issue (USB-based stdout reading doesn't work — turned out not to matter, since the framebuffer console above is the real confirmation channel).

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
