# OMERTA iOS — iPhone 6 Boot Environment Project

Target hardware: **iPhone 6** — Apple A8, platform codename **s8000**, checkm8-vulnerable (SecureROM exploit, unpatchable in hardware). Covered by upstream `checkra1n`/`pongoOS`.

This repo is organized in stages so we never pretend a tweak `.deb` or a Pongo binary is a signed IPSW. Each stage is real and independently useful; nothing here bypasses Apple code signing on the actual iOS kernel/userspace — it operates in the pre-boot (SecureROM/Pongo) environment and, for phase1, the userspace jailbreak/tweak layer.

```
                    OMERTA iOS
                         |
                 +---------------+
                 | DFU / checkm8 |
                 +-------+-------+
                         |
                 +---------------+
                 |   pongoOS      |
                 | + OMERTA module|
                 | boot environment|
                 +-------+-------+
                         |
             +-----------+-----------+
             |                       |
      OMERTA boot status      iOS/XNU boot
       (Pongo shell)           (stock, via bootx)
             |                       |
             +-----------+-----------+
                         |
                 OMERTA userspace
                 (phase1 jailbreak/tweak layer)
```

## Current blocker (read this first)

**Update 2026-09-08: the test iPhone 6 is Activation Locked again, and this time it's presumed fully erased.** `phase3/ramdisk/`'s patched-RestoreRamDisk boot attempt was tested live against the real device and, instead of booting an isolated RAM-only environment as intended, triggered what looks like Apple's real erase-install process — the device now sits at Setup Assistant's Activation Lock screen, phase1's jailbreak/tweak install and any personal data are presumed wiped. Full details in `phase3/README.md`'s `ramdisk/` section. **Do not repeat that ramdisk-boot approach.** As before, there's no legitimate software fix for Activation Lock and none should be attempted (original owner, Apple Support + proof of purchase, or an MDM bypass code for an enterprise unit are the only real paths — or test on a second, clean iPhone 6/6s-class device instead). All further on-device work across every phase is blocked until the device is recovered through one of those paths, or a replacement test device is available.

Prior to that incident: Phase 1's tweak was code-complete, verified over SSH, and had been seen booting correctly into a working jailbroken SpringBoard (installs cleanly, hook fires, Keychain PIN write confirmed via syslog, no crash-loop). That working state is what's presumed lost. See `phase1/README.md` for the full history, including why this repo's `phase2/` (pongoOS) is a separate, host-side-only track unaffected by device state.

## Directory layout

| Path | Status | What it is |
|---|---|---|
| `phase1/` | **merged, real-device-tested (presumed wiped 2026-09-08)** | Jailbreak + Theos tweak/toolchain work (checkra1n bootstrap, Theos, Odyssey headless debug). From `OMERTA-iOS-Phase1-final.zip`. Blocked on the Activation-Lock issue above. |
| `phase2/` | **built in this scaffold** | pongoOS boot environment: build system, OMERTA Pongo module (`omerta_boot`), boot/status screen, checkra1n `-k` wrapper. Host-side/pre-boot only — unaffected by device state. |
| `phase3/` | **partially built; ramdisk sub-effort abandoned (destructive)** | `userspace/omerta-persistd/`: LaunchDaemon persistence, built and verified on real hardware pre-incident. `ramdisk/`: patched-RestoreRamDisk boot PoC — tried live, erased the device, abandoned. `kernel/`, `rootfs/`: not started, explicitly out of scope (multi-month research project). See `phase3/README.md`. |
| `emulator/` | **parked** | Side-investigation into testing phase1's SpringBoard-tweak logic via `xnu-qemu-arm64` (a different device/SoC than this project's real iPhone 6 target) while the real device is unusable. Real progress made (KVM confirmed, Linux `hfsplus` RW mount confirmed working), but parked after hitting a Linux-vs-macOS `com.apple.decmpfs` decoding wall. No bearing on phase2/phase3. See `emulator/README.md`. |
| `tools/` | scaffolded | `dfu/` device detection, `diagnostics/`, `packaging/` — device-agnostic helper scripts. |
| `output/` | empty | CI-built artifacts land here when you download them from GitHub Actions (see below). |
| `.github/workflows/build-pongo.yml` | **built** | Builds `Pongo.bin` / `PongoConsolidated.bin` and the `omerta_boot` module in CI, since building the Linux toolchain (`ld64`, `cctools-strip`) directly on-device in Termux is impractical. |

## Quick start

1. **Push this to a GitHub repo** (e.g. `dardybrah-ux/omerta-ios`, matching your existing project naming).
2. GitHub Actions builds automatically on push (see workflow below) — or trigger manually from the Actions tab.
3. Download the `pongo-build` artifact from the finished run; unzip into `output/`.
4. On a host machine with `checkra1n` and USB access to the iPhone 6 in DFU mode:
   ```
   checkra1n -k output/Pongo.bin              # bare Pongo shell, no KPF
   checkra1n -k output/PongoConsolidated.bin  # auto-runs KPF, boots to XNU
   checkra1n -k output/PongoConsolidated.bin -p   # KPF loaded, stays in Pongo shell
   ```
5. Once in the Pongo shell (serial/USB, text-mode — see `phase2/README.md`), run `omerta` to see the OMERTA boot status banner, or load the module manually with `phase2/tools/omerta_load.py output/omerta_boot`.

## What this is *not* (yet)

- Not a signed IPSW. Nothing here goes through Apple's restore/signing chain.
- Not a graphical boot logo — pongoOS's own framebuffer driver exists (`fb.c` upstream) but the OMERTA module here is text/serial-console only for phase2. A graphical OMERTA splash is a phase3 candidate once we've proven the module loads and boots reliably.
- Not persistent — Pongo and the OMERTA module live in RAM only, pushed fresh over USB every boot (this is normal for checkm8-class tethered tooling, same as checkra1n itself). Persistence is a phase3 problem.

See `PLAN.md` for the full staged roadmap and technical notes.
