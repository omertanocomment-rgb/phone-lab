# Phase 1 — jailbreak + tweak layer

```
iPhone 6 → checkra1n → jailbroken iOS → Theos/tweaks → OMERTA components
```

```
phase1/
├── OMERTA-iOS-PLAN.md              the reality-check + tweak roadmap (its own 5-phase plan — see note below)
├── install-omerta-ios.sh           end-to-end scripted install (bootstrap + libhooker + tweak, with recovery for the known dpkg/apt bugs)
├── OMERTAiOS-tweak/                Theos tweak source: OwnerLock.{h,m}, OMLockViewController.{h,m}, Tweak.xm, control, Makefile
│   └── packages/                   the built, real-device-tested .deb
└── toolchain/
    ├── 01-jailbreak-iphone6-checkra1n.md
    ├── 02-theos-bootstrap-mint.sh
    └── 03-odyssey-bootstrap-and-headless-debug.md
```

## Current real status (from `OMERTA-iOS-PLAN.md` / the tweak's own README)

Confirmed correct end-to-end except the last, purely visual step:

- `.deb` installs cleanly, no dependency errors.
- The tweak's hook fires on SpringBoard launch.
- PIN storage genuinely writes to the Keychain (confirmed independently via `securityd`'s syslog output).
- **Not yet confirmed:** actually seeing the lock overlay render on screen. The specific test unit is iCloud Activation Locked from a previous owner, which blocks Setup Assistant and causes an unrelated SpringBoard crash-loop. This is *not* a defect in the tweak (confirmed by removing it and observing the same crash behavior) and it is explicitly **not something to work around** — Activation Lock has no legitimate software bypass. The path forward is the original account holder, Apple Support with proof of purchase, or an MDM bypass code for an enterprise-owned unit — or testing on a second, non-locked iPhone 6/6s-class device instead.

Per the plan doc's own rule: **do not start the tweak's Phase 2 (duress PIN) until visual confirmation happens for real on a working device.** That rule is untouched by anything in `../phase2/` — see the note below.

## Two different "Phase 2"s in this repo — read this before it's confusing

`OMERTA-iOS-PLAN.md` in this directory has its **own** 5-phase roadmap, entirely about the tweak's feature set:

1. Owner-lock overlay (built, pending visual confirmation)
2. Duress PIN
3. Safe Mode
4. Hidden control hub
5. Package as `.deb`

That numbering is internal to `phase1/` and is currently **paused** at step 1, by the plan's own explicit rule, until the Activation-Lock blocker is resolved on real hardware.

The repo root's `PLAN.md` uses "Phase 1 / Phase 2 / Phase 3" for something different and unrelated: Phase 1 = this whole directory (the jailbreak + tweak layer, regardless of internal step), Phase 2 = the `pongoOS` pre-boot environment in `../phase2/`, Phase 3 = future persistent kernel/rootfs work. The root Phase 2 (pongoOS) doesn't touch SpringBoard, the tweak, or Activation Lock at all — it operates entirely before iOS ever boots — so it isn't "ahead of" anything the tweak's own Phase 2 rule is guarding against. Just don't let "Phase 2" in a sentence be ambiguous about which tree it means.

## What's in `install-omerta-ios.sh`

An idempotent, headless installer: bootstraps dpkg/apt/Sileo on a
checkra1n'd device over SSH (with automatic recovery from two real
dpkg/apt bugs — a `MaxLoopCount` cycle and an apt segfault mid-upgrade),
installs LibHooker as the mobilesubstrate provider, then builds/installs
`OMERTAiOS-tweak`. Optionally walks through setting a temporary test PIN
(via a scratch `Tweak.xm` copy that's restored afterward, so no PIN ever
lands in source) and installing an SSH key for passwordless access. Run
`./install-omerta-ios.sh --help` for options.

## Why it matters for phase2

`toolchain/01-jailbreak-iphone6-checkra1n.md` should stay consistent with
`../phase2/README.md` and `../tools/dfu/detect.sh` on how they talk to the
iPhone 6 in DFU/checkra1n mode, rather than keeping two separate procedures
for the same device — worth a pass to fold them together.
