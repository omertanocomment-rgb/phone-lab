# OMERTAiOS-tweak (Phase 1: owner-lock overlay)

A Theos tweak for jailbroken iOS (checkra1n, iPhone 6 / iOS 12.5.8) that
hooks SpringBoard and demands an owner PIN before the real home screen
becomes usable. This is the iOS-native starting point for OMERTA's iOS
build -- see `../OMERTA-iOS-PLAN.md` for why this exists and what an
Android APK cannot do here, plus the phase roadmap.

## Prerequisites

1. iPhone 6 jailbroken via checkra1n (`../toolchain/01-jailbreak-iphone6-checkra1n.md`).
2. Theos + an iOS SDK installed on this Linux Mint box
   (`../toolchain/02-theos-bootstrap-mint.sh`).
3. OpenSSH installed on the phone via Sileo/Cydia, so the built `.deb` can
   be copied over.

## Build

```bash
export THEOS=$HOME/theos   # only needed if not already in your shell profile
make package
```

Output lands in `packages/com.omerta.iosui_0.1.0_iphoneos-arm64.deb`.

## Set an owner PIN (Phase 1 has no UI for this yet)

There's no in-tweak settings screen yet -- Phase 1 is deliberately just the
lock-screen mechanism so it can be tested in isolation first. Set a PIN by
SSHing into the phone after installing the tweak and running a one-off
`hasOwnerPin`/`setOwnerPin` call. The cleanest way to do that without
building a second binary: add a temporary `constructor` block to `Tweak.xm`
that calls `[OMOwnerLock setOwnerPin:@"1234"]` once, rebuild, install,
respring, then remove that block and rebuild again so the PIN-setting code
doesn't ship permanently. A real settings UI for this is Phase 2+ work,
alongside duress/Safe Mode.

## Install on the phone

```bash
scp packages/com.omerta.iosui_0.1.0_iphoneos-arm64.deb root@<phone-ip>:/var/mobile/
ssh root@<phone-ip> "dpkg -i /var/mobile/com.omerta.iosui_0.1.0_iphoneos-arm64.deb; killall -9 SpringBoard"
```

SpringBoard respawns automatically after `killall`; that's expected and is
how the tweak takes effect without a full reboot.

## Test plan

1. Install with no PIN set yet -- SpringBoard should behave completely
   normally (the hook checks `hasOwnerPin` and does nothing if it's unset).
2. Set a PIN using the constructor-block trick above, rebuild, reinstall,
   respring.
3. Confirm the black "Enter Passcode" screen appears over SpringBoard
   immediately after the respring, on top of everything.
4. Confirm a wrong PIN shows "Incorrect passcode" and clears the field.
5. Confirm the correct PIN dismisses the overlay and reveals the real
   SpringBoard underneath.
6. Confirm surviving a full reboot (remember: checkra1n itself is
   semi-tethered, so you'll need to redo the checkra1n DFU steps to get
   back into a jailbroken boot at all -- separate from this tweak's own
   behavior, which should persist across that as long as the `.deb` stays
   installed).

Do not start Phase 2 (duress PIN) until this checklist passes for real on
the device.
