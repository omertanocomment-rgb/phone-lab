# Phase 1 — jailbreak + tweak layer

```
iPhone 6 → checkra1n → jailbroken iOS → Theos/tweaks → OMERTA components
```

Merged in from the standalone `OMERTAiOS-tweak` build:

```
phase1/
├── OMERTA-iOS-PLAN.md         # reality-check + staged build plan (superseded day-to-day by ../PLAN.md)
├── install-omerta-ios.sh      # scripted headless install: bootstrap dpkg/apt/Sileo, LibHooker, then the tweak
├── OMERTAiOS-tweak/           # Objective-C/Theos tweak source (owner-lock overlay)
└── toolchain/
    ├── 01-jailbreak-iphone6-checkra1n.md
    ├── 02-theos-bootstrap-mint.sh
    └── 03-odyssey-bootstrap-and-headless-debug.md
```

## What's in `install-omerta-ios.sh`

An idempotent, headless installer: bootstraps dpkg/apt/Sileo on a
checkra1n'd device over SSH (with automatic recovery from two real
dpkg/apt bugs — a `MaxLoopCount` cycle and an apt segfault mid-upgrade),
installs LibHooker as the mobilesubstrate provider, then builds/installs
`OMERTAiOS-tweak`. Optionally walks through setting a temporary test PIN
(via a scratch `Tweak.xm` copy that's restored afterward, so no PIN ever
lands in source) and installing an SSH key for passwordless access. Run
`./install-omerta-ios.sh --help` for options.

## What's in `OMERTAiOS-tweak/`

A Theos tweak that hooks SpringBoard and demands an owner PIN (PBKDF2-hashed,
stored in the Keychain) before the real home screen becomes usable. See
`OMERTAiOS-tweak/README.md` for build/install/test steps. Build artifacts
(`.theos/`, `packages/*.deb`, restore logs) were intentionally left out of
this merge — they're local build scratch, not source.

## Why it matters for phase2

`toolchain/01-jailbreak-iphone6-checkra1n.md` should stay consistent with
`../phase2/README.md` and `../tools/dfu/detect.sh` on how they talk to the
iPhone 6 in DFU/checkra1n mode, rather than keeping two separate procedures
for the same device — worth a pass to fold them together.
