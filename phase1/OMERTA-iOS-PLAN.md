# OMERTA iOS — Reality Check + Build Plan

## Correcting "custom IPSW"

An Android APK cannot be dropped into an iPhone restore image and boot as the
OS. Android and iOS share nothing at the level that matters here: different
kernel (Linux vs XNU/Darwin), different app runtime (JVM/ART + Kotlin/Java vs
Objective-C/Swift + UIKit), different bootloader/signing model (Android
bootloader vs iBoot + Apple code-signing), different init system, everything.
There is no "convert this APK" step. OMERTA UI as it exists cannot become the
iPhone 6's OS.

What *is* real and achievable, and matches what you actually asked for
("boot into a custom OS based off of this launcher"):

1. **Jailbreak the iPhone 6 on iOS 12.5.8.** The A8 chip is checkm8-vulnerable
   (bootrom exploit, can never be patched by Apple), so this device is a
   permanent jailbreak target regardless of software version. Tool: **checkra1n**
   (Linux build exists, supports iPhone 5s through iPhone X, works with A8
   -- only A7 is excluded on the Linux build). ([checkra.in](https://checkra.in/))
   `palera1n` is NOT an option here -- it requires iOS/iPadOS 15.0+
   ([palera1n GitHub](https://github.com/palera1n/palera1n)), and the iPhone 6
   can't run past iOS 12 regardless, so that's a hard mismatch.
   checkra1n's jailbreak is **semi-tethered**: after every reboot you have to
   reconnect the phone to your Linux Mint box and re-run checkra1n to get back
   into the jailbroken state. That's a real operational cost, not a one-time
   step.

2. **Once jailbroken, build a native SpringBoard-replacement tweak** using
   **Theos** (the standard jailbreak dev toolchain -- and it genuinely runs on
   Linux, no Mac required: [theos.dev/docs/installation-linux](https://theos.dev/docs/installation-linux)).
   This is the actual mechanism for "boot into a custom OS based off of this
   launcher": a tweak that hooks SpringBoard (the process that owns the iOS
   home screen/lock screen) and takes over its UI at launch, the same way a
   jailbreak theme or lock-screen tweak does -- except built from scratch to
   carry over OMERTA UI's actual feature set instead of someone else's theme.

   This means a ground-up **native rewrite** in Objective-C, not a port of
   the Android Java/Kotlin code. The concepts carry over (owner PIN, duress
   PIN, Safe Mode, the hidden control hub, the privacy tools); the code does
   not.

## What's built right now (Phase 1)

A real, from-scratch Theos tweak project, `OMERTAiOS-tweak/`, implementing
the owner-lock overlay:

- `OwnerLock.h` / `OwnerLock.m` -- PBKDF2-SHA256 (120,000 iterations, 256-bit),
  salted, stored in the iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
  -- the iOS analog of `OwnerLockManager`'s AndroidKeyStore-backed storage on
  the Android side.
- `OMLockViewController.h` / `.m` -- full-screen PIN-entry screen.
- `Tweak.xm` -- hooks `SpringBoard -applicationDidFinishLaunching:` and, if an
  owner PIN is set, throws up a max-window-level `UIWindow` blocking
  interaction with the real home screen until the PIN is entered correctly.
- `control` / `Makefile` -- standard Theos package metadata and build rules,
  targeting `arm64` (compiled CPU arch), packaged under the
  `iphoneos-arm` dpkg architecture tag (not Theos's default
  `iphoneos-arm64` -- see below), minimum iOS 12.0.

## Current status (updated after real-device testing)

This has now gone through a full live debugging session on real hardware
(checkra1n iPhone 6, iOS 12.5.8) -- built with Theos, packaged, and
installed via dpkg with all dependencies (including `mobilesubstrate`, via
CoolStar's LibHooker) correctly resolved. Everything encountered along the
way -- getting dpkg/apt/Sileo onto the device with zero touchscreen
interaction, a dpkg `MaxLoopCount` cycle bug, an apt segfault, and an
architecture-tag mismatch between Theos's default output and this
bootstrap's dpkg convention -- is written up in
`toolchain/03-odyssey-bootstrap-and-headless-debug.md`.

**What's confirmed working:** the `.deb` installs cleanly (`ii` status, no
dependency errors), the tweak's hook fires on SpringBoard launch, and its
Keychain-backed PIN storage (`OwnerLock.m`) genuinely writes to the
Keychain -- confirmed independently via `securityd`'s own syslog output
(`inserted <genp...svce=com.omerta.iosui.ownerlock...acct=owner_hash...>`),
captured live over SSH with `idevicesyslog`.

**What's not yet confirmed:** actually seeing the lock overlay rendered on
screen. The specific test unit used this session turned out to be iCloud
Activation Locked from a previous owner (discovered via 3uTools' Batch
Activate/Erase screen) -- this blocks Apple's own Setup Assistant from ever
completing and appears to also cause an intermittent SpringBoard
crash-loop, unrelated to this tweak's own code (confirmed by removing the
tweak entirely and observing the same crash behavior persisted). This is a
property of that one secondhand unit, not a defect in this project, and it
is **not something to work around** -- Activation Lock is an anti-theft
mechanism and there is no legitimate software bypass; see the toolchain doc
for the legitimate paths (original account holder, Apple Support + proof of
purchase, or an MDM bypass code for enterprise-owned devices).

**Net effect:** Phase 1's code is validated as correct through every layer
that can be checked without a working, unlocked display. The remaining
step -- watching the actual overlay render and testing the PIN-entry flow
end-to-end -- needs either this same phone with its Activation Lock
resolved through one of those legitimate paths, or a second, verified
non-locked iPhone 6/6s-class device to test on instead. Do not start Phase
2 until that visual/interactive confirmation happens for real.

**Independently re-confirmed 2026-09-07/08, separate session:** same unit,
still Activation Locked (confirmed directly on-screen this time, not just
inferred from the crash-loop) -- unchanged, no legitimate bypass attempted
or suggested. Re-verified the same "confirmed working" claims from a fresh
install: `libhooker: Loading for binary SpringBoard` /
`Injecting /usr/lib/TweakInject/OMERTAiOS.dylib` in syslog confirms the
tweak actually loads, and a fresh `%ctor`-set test PIN produced clean
`securityd` delete+insert pairs for both `owner_salt` and `owner_hash`
under `svce=com.omerta.iosui.ownerlock`, captured live via `idevicesyslog`
during the respring. Same conclusion as before, now cross-checked twice.

## Roadmap (do NOT build ahead of testing -- same rule as the Android side)

- **Phase 1 (built):** Owner-lock overlay on SpringBoard launch.
- **Phase 2:** Duress PIN -- a second PIN that satisfies the lock screen but
  routes into a decoy view instead of dismissing to the real home screen.
- **Phase 3:** Safe Mode -- a third PIN that dismisses into a plain,
  unbranded SpringBoard-like app list (mirrors `SafeModeHomeActivity`), with
  a secret gesture back into the real control hub authenticated by the real
  PIN.
- **Phase 4:** Hidden control hub -- the iOS equivalent of `ControlActivity`,
  reachable only via the secret gesture, hosting whichever of the Android
  privacy tools have a real iOS equivalent (Keychain-backed clipboard clear,
  installed-profile/enterprise-app auditing via `MCProfile`/`LSApplicationWorkspace`
  where entitlements allow, etc. -- this needs its own audit once jailbroken,
  since iOS's introspection APIs are not a 1:1 match for Android's
  `PackageManager`).
- **Phase 5:** Package as a `.deb` (Theos already does this via `make package`)
  and install through the jailbreak's package manager (Sileo/Zebra).

Each phase gets built, delivered, and tested on the real device before the
next one starts -- exactly the discipline we've been using on the Android
side.
