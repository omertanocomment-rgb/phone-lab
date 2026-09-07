# OMERTAiOS-tweak (Phase 1: owner-lock overlay)

A Theos tweak for jailbroken iOS (checkra1n, iPhone 6 / iOS 12.5.8) that
hooks SpringBoard and demands an owner PIN before the real home screen
becomes usable. This is the iOS-native starting point for OMERTA's iOS
build -- see `../OMERTA-iOS-PLAN.md` for why this exists and what an
Android APK cannot do here, plus the phase roadmap.

**Status: code validated end-to-end on real hardware (checkra1n iPhone 6,
iOS 12.5.8) -- built, installed cleanly with all dependencies resolved, and
its Keychain/hook logic independently confirmed correct via live syslog.
Final on-screen visual confirmation is blocked on the specific unit this
was tested on, which turned out to be iCloud Activation Locked from a
previous owner (unrelated to this project -- see
`../toolchain/03-odyssey-bootstrap-and-headless-debug.md`, section 5). On a
normal, fully set-up device none of that applies.**

## Quick install (recommended)

A real, already-compiled `.deb` is included at
`packages/com.omerta.iosui_0.1.0_iphoneos-arm.deb` -- built and verified in
this repo's own build environment (Theos + the `iPhoneOS12.4.sdk`, targeting
`iphoneos-arm` to match this project's bootstrap), so you don't need Theos
installed just to try it. Confirmed via `dpkg-deb --info`/`--contents`: a
genuine `Mach-O 64-bit arm64` dylib, correctly staged at
`/Library/MobileSubstrate/DynamicLibraries/`, with `Depends: firmware (>=
12.0), mobilesubstrate` and `Architecture: iphoneos-arm` set correctly.

The whole install process from `../toolchain/03-odyssey-bootstrap-and-headless-debug.md`
(dpkg/apt/Sileo bootstrap, LibHooker, this package, all the recovery steps
for the dpkg/apt bugs hit along the way) is scripted end-to-end in
`../install-omerta-ios.sh`:

```bash
cd ..
./install-omerta-ios.sh -p <your-ssh-tunnel-port>
```

Run `./install-omerta-ios.sh --help` for the full option list (passwordless
SSH key setup, skipping the bootstrap if dpkg is already installed, an
interactive prompt to set a temporary test PIN). It's safe to re-run -- every
step checks whether it's already done first.

## Prerequisites (if not using the script above)

1. iPhone 6 jailbroken via checkra1n (`../toolchain/01-jailbreak-iphone6-checkra1n.md`).
2. Theos + an iOS SDK installed on this Linux Mint box
   (`../toolchain/02-theos-bootstrap-mint.sh`).
3. dpkg/apt/Sileo on the phone. If you jailbroke through checkra1n's own
   on-device app and tapped through its Cydia/Sileo install, you already
   have this. If you're doing this entirely headless (no working
   touchscreen), see `../toolchain/03-odyssey-bootstrap-and-headless-debug.md`
   for the full zero-touch bootstrap procedure -- it also covers the
   `MaxLoopCount`/apt-segfault issues that can come up partway through.
4. A `mobilesubstrate`-providing injection framework installed on the
   phone. On the old-style rootful Odyssey/Procursus bootstrap this project
   was built and tested against, that's CoolStar's LibHooker, **not**
   ellekit (which targets rootless iOS 15+ and isn't relevant to iOS 12):

   ```bash
   apt-get install -y --allow-unauthenticated org.coolstar.libhooker
   ```

   If you're on a different/newer bootstrap, check what actually provides
   `mobilesubstrate` there first -- don't assume either name.
5. OpenSSH on the phone, so the built `.deb` can be copied over.

## Build

```bash
export THEOS=$HOME/theos   # only needed if not already in your shell profile
make package
```

Output lands in `packages/com.omerta.iosui_0.1.0_iphoneos-arm.deb`.

**A note on the `Architecture:` tag in `control`:** this repo ships with
`Architecture: iphoneos-arm`, *not* Theos's default `iphoneos-arm64`. That's
deliberate, not a typo -- the old-style rootful Odyssey/Procursus bootstrap
this was built against uses `iphoneos-arm` as its one universal
architecture tag for everything (`dpkg --print-foreign-architectures` on
the device comes back empty, so `iphoneos-arm64` isn't even a registered
architecture there). A tweak packaged under the wrong tag will still
`dpkg -i --force-architecture` its way onto the device, but its
`Depends: mobilesubstrate` will then silently fail to resolve even with
LibHooker correctly installed and working, because dpkg's dependency
matching is architecture-scoped. If you're targeting a different/newer
bootstrap (e.g. a rootless iOS 15+ one), check what architecture tag *that*
bootstrap actually uses before building -- see
`../toolchain/03-odyssey-bootstrap-and-headless-debug.md` section 3 for the
full story of how this was diagnosed.

## Set an owner PIN (Phase 1 has no UI for this yet)

There's no in-tweak settings screen yet -- Phase 1 is deliberately just the
lock-screen mechanism so it can be tested in isolation first. Set a PIN by
SSHing into the phone after installing the tweak and running a one-off
`hasOwnerPin`/`setOwnerPin` call. The cleanest way to do that without
building a second binary: add a temporary `constructor` block to `Tweak.xm`
that calls `[OMOwnerLock setOwnerPin:@"1234"]` once, rebuild, install,
respring, then remove that block and rebuild again so the PIN-setting code
doesn't ship permanently (never leave a hardcoded PIN in a build you
actually deploy). A real settings UI for this is Phase 2+ work, alongside
duress/Safe Mode.

## Install on the phone

```bash
scp packages/com.omerta.iosui_0.1.0_iphoneos-arm.deb root@<phone-ip>:/var/mobile/
ssh root@<phone-ip> "dpkg -i /var/mobile/com.omerta.iosui_0.1.0_iphoneos-arm.deb; killall -9 SpringBoard"
```

SpringBoard respawns automatically after `killall`; that's expected and is
how the tweak takes effect without a full reboot.

If `dpkg -i` reports a dependency problem on `mobilesubstrate` even though
LibHooker is installed, that's almost certainly the architecture-tag issue
described above, not a real missing dependency -- check `control` before
anything else.

## Verifying it without a working touchscreen

If the phone's screen is broken/unresponsive (as it was for the device
this was developed against), you can still fully verify the tweak over SSH
-- screenshots via `idevicescreenshot` (needs the Developer Disk Image
mounted) and, more reliably, live syslog capture via `idevicesyslog`
grepped for `NSLog` checkpoints, which confirms hook-firing and
Keychain-write logic independent of the display/lock state entirely. Full
walkthrough, including how to read a crash report if SpringBoard starts
respring-looping: `../toolchain/03-odyssey-bootstrap-and-headless-debug.md`.

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
