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
  targeting `arm64`, `iphoneos-arm64`, minimum iOS 12.0.

This is unverified against a real device/SDK (there's no Xcode or iOS SDK
in the environment this was written in) -- syntax was hand-checked for
balanced braces/parens, but the actual compile-and-run test only happens on
your Linux Mint box once Theos + the SDK are installed. Treat this the same
way we treated build-termux.sh and build-kali.sh: first real build is the
real test.

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
