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

Phase 1's tweak is code-complete and verified over SSH (installs cleanly, hook fires, Keychain PIN write confirmed via syslog) but the on-screen lock overlay has never actually been *seen* — the test iPhone 6 turned out to be iCloud Activation Locked by a previous owner, which crash-loops SpringBoard independent of this tweak. There's no legitimate software fix for Activation Lock and none should be attempted (original owner, Apple Support + proof of purchase, or an MDM bypass code for an enterprise unit are the only real paths — or test on a second, clean iPhone 6/6s-class device instead). Per the plan's own rule, the tweak's *internal* Phase 2 (duress PIN) stays paused until that visual confirmation happens for real. See `phase1/README.md` for the full picture, including why this repo's own `phase2/` (pongoOS) is a separate, unaffected track.

## Directory layout

| Path | Status | What it is |
|---|---|---|
| `phase1/` | **merged, real-device-tested** | Jailbreak + Theos tweak/toolchain work (checkra1n bootstrap, Theos, Odyssey headless debug). From `OMERTA-iOS-Phase1-final.zip`. Currently blocked on the Activation-Lock issue above. |
| `phase2/` | **built in this scaffold** | pongoOS boot environment: build system, OMERTA Pongo module (`omerta_boot`), boot/status screen, checkra1n `-k` wrapper. Unaffected by the phase1 blocker — operates entirely pre-boot. |
| `phase3/` | stub | Future: persistent kernel/ramdisk/userspace/rootfs work. Not started — this is the "genuine custom OS" tier and depends on what phase2 proves out. |
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
