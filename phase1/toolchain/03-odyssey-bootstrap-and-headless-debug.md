# Getting dpkg/Sileo onto a checkra1n device with zero touchscreen interaction, and debugging it headless

This doc captures everything learned getting OMERTAiOS-tweak actually built,
installed, and verified on a real iPhone 6 (iOS 12.5.8) whose touchscreen is
non-functional -- every step below was done entirely over SSH from a Linux
box, with the phone's own screen never touched. Written after a long live
debugging session; keep it updated if anything here goes stale.

## 0. Starting point

- iPhone 6, iOS 12.5.8, jailbroken via checkra1n (see `01-jailbreak-iphone6-checkra1n.md`).
- SSH reachable over USB via a 3uTools-style tunnel (`127.0.0.1:<port>`,
  `root`/`alpine`). Any USB SSH tunnel works the same way -- 3uTools just
  happens to make one easy to set up from a GUI. `iproxy` from
  `libimobiledevice` does the same thing directly if you don't have 3uTools.
- checkra1n's own environment has SSH but **no package manager at all** --
  no dpkg, no apt. Normally you'd tap through checkra1n's on-device app to
  install Sileo/Cydia. With no working touchscreen, that's not an option.

## 1. Installing dpkg + apt + Sileo headlessly (Odyssey bootstrap)

`coolstar/Odyssey-bootstrap` on GitHub ships the actual Procursus bootstrap
Apple-Configurator-adjacent tooling normally drives through checkra1n's app.
Its `procursus-deploy-linux-macos.sh` wraps: downloading a bootstrap tarball,
scp-ing it to the device, and running an install script on-device. The
wrapper script defaults to opening its own `iproxy` tunnel -- skip that and
reuse whatever SSH tunnel you already have.

Pick the right bootstrap file for your iOS major version:
`bootstrap_1500.tar.gz` = iOS 12.x, `1600` = 13.x, `1700` = 14.x. Only
`org.swift.libswift` is needed in addition for iOS 12.0.x/12.1.x specifically
(not needed for 12.5.x).

```bash
cd /tmp
curl -fsSL -O https://github.com/coolstar/Odyssey-bootstrap/raw/master/bootstrap_1500.tar.gz
curl -fsSL -O https://github.com/coolstar/Odyssey-bootstrap/raw/master/org.coolstar.sileo_2.3_iphoneos-arm.deb
# The on-device install script itself is a heredoc inside procursus-deploy-linux-macos.sh
# -- extract it directly from the real source rather than retyping it, to
# avoid transcription bugs: `curl -fsSL -o /tmp/procursus-deploy.sh https://raw.githubusercontent.com/coolstar/Odyssey-bootstrap/master/procursus-deploy-linux-macos.sh`,
# then `grep -n 'cat << "EOF"'` to find the exact line range and `sed -n
# 'START,ENDp'` it out to its own file.

scp -O -P <PORT> bootstrap_1500.tar.gz org.coolstar.sileo_2.3_iphoneos-arm.deb odysseyra1n-install.bash root@127.0.0.1:/var/root/
ssh -p <PORT> root@127.0.0.1 "cd /var/root && bash odysseyra1n-install.bash"
```

Safety check before running: `ssh ... "ls /.bootstrapped /.installed_odyssey"`
should report both missing -- if either exists, this device was already
bootstrapped/migrated and re-running can be destructive.

The phone needs its own Wi-Fi for the `apt-get update && dist-upgrade`
portion at the end (separate from the USB tunnel). The script wipes and
regenerates `/etc/ssh`, so your next SSH connection will throw a
host-key-changed warning -- `ssh-keygen -R "[127.0.0.1]:<PORT>"` clears it.

### Gotcha: `MaxLoopCount reached in SmartUnPack` during the final dist-upgrade

This is dpkg's own cycle-breaker hitting its retry cap on a Pre-Depends loop
(`libiosexec1` here), not corruption -- `dpkg --audit` will show nothing
actually broken. Fix: pull the blocking package's `.deb` straight out of
apt's own cache and force it in directly, bypassing apt's whole-batch
ordering pass entirely, then retry the batch upgrade:

```bash
ls /var/cache/apt/archives/ | grep -i libiosexec
dpkg -i --force-depends /var/cache/apt/archives/libiosexec1_*.deb
apt-get -o APT::Immediate-Configure=0 dist-upgrade -y --allow-downgrades --allow-unauthenticated
```

If the *old* `apt` binary itself segfaults calculating the upgrade (it can,
on a device this old jumping many versions at once), same trick again --
force just `apt`/`libapt-pkg6.0` in from cache first, then retry:

```bash
dpkg -i --force-depends /var/cache/apt/archives/libapt-pkg6.0_*.deb /var/cache/apt/archives/apt_*.deb
```

Conffile prompts (`ca-certificates`, `dpkg`'s own origins file, `sudo`,
`sudoers`) will appear during the upgrade -- answer `I` (install
maintainer's version) unless you specifically know you want to keep a
locally modified file, which you won't on a fresh bootstrap.

## 2. Installing an injection framework (mobilesubstrate)

Odyssey's bootstrap gives you dpkg/apt/Sileo but *not* a tweak-injection
framework -- Theos-built tweaks need `Depends: mobilesubstrate` satisfied.
`ellekit` (the modern replacement) is built for rootless iOS 15+ bootstraps
and won't be in the repo list for an old-style rootful iOS 12 bootstrap like
this. What actually provides `mobilesubstrate` here is CoolStar's LibHooker:

```bash
apt-get install -y --allow-unauthenticated org.coolstar.libhooker
```

## 3. The architecture-tag gotcha

Theos defaults new tweak projects to `Architecture: iphoneos-arm64` in
`control`. **This old-style rootful Procursus/Odyssey bootstrap uses
`iphoneos-arm` as its one universal architecture tag for everything** --
`dpkg --print-foreign-architectures` on the device comes back empty, meaning
`iphoneos-arm64` isn't a registered architecture at all here. A tweak
packaged as `iphoneos-arm64` will install fine with `dpkg -i
--force-architecture`, but its `Depends:` (e.g. on `mobilesubstrate`) will
silently fail to resolve even when the actual provider is installed and
working, because dpkg is checking for a same-architecture match and finding
none. The fix isn't another force flag -- it's repackaging under the
architecture this bootstrap actually uses (the compiled Mach-O binary itself
doesn't change, only the dpkg metadata):

```bash
sed -i 's/^Architecture: iphoneos-arm64$/Architecture: iphoneos-arm/' control
make package   # no need for `make clean` -- this is a repackage, not a rebuild
```

This repo's `control` is already set to `iphoneos-arm` for exactly this
reason. If you're building for a newer rootless bootstrap (iOS 15+), check
what architecture *that* bootstrap actually uses before assuming either tag.

## 4. Verifying it worked with no working screen

Two independent techniques, used together:

### Screenshots via `idevicescreenshot`

Needs the Developer Disk Image mounted (normally an Xcode-only step) and a
one-time `idevicepair pair` (worked here with no on-screen trust-tap needed
-- checkra1n's environment doesn't seem to enforce it the way stock iOS
does). DDIs for old iOS versions: `github.com/iGhibli/iOS-DeviceSupport`. A
DDI one minor version behind the device (12.4 DDI on a 12.5.8 device) works
fine for basic services like screenshotr.

```bash
sudo apt install -y libimobiledevice-utils
idevicepair pair
curl -fsSL -o ddi.zip "https://github.com/iGhibli/iOS-DeviceSupport/raw/master/DeviceSupport/12.4%20(16G73).zip"
mkdir -p ddi && unzip -o ddi.zip -d ddi
ideviceimagemounter "ddi/12.4 (16G73)/DeveloperDiskImage.dmg" "ddi/12.4 (16G73)/DeveloperDiskImage.dmg.signature"
idevicescreenshot out.png
```

If it fails right after mounting with "Invalid service," just retry after a
couple seconds -- lockdownd needs a moment to register the new service.

**A device sitting idle for a while (common mid-debugging-session) will
auto-lock and every screenshot will come back solid black.** Don't
mis-diagnose this as a tweak bug -- check `dpkg -l | grep -v '^ii'` for
actually-broken packages first, and compare pixel data across captures
(`PIL`'s `getcolors()`) before concluding anything from a black screenshot.

### syslog, for verifying tweak logic independent of the screen entirely

Far more reliable than screenshots for confirming a hook's *logic* is
running, since it doesn't depend on display/lock state at all:

```bash
timeout 15 idevicesyslog > /tmp/syslog.txt &
ssh -p <PORT> root@127.0.0.1 "killall -9 SpringBoard"
wait
grep -i omerta /tmp/syslog.txt
```

Add `NSLog(@"[OMERTA] ...")` checkpoints through the code you're verifying,
grep the tag. This is how Phase 1's PIN-storage-via-Keychain and hook-firing
logic were confirmed correct on the real device even though the lock overlay
itself was never actually seen rendered (see "Known issue" below) --
`securityd`'s own log lines (`inserted <genp...svce=com.omerta.iosui.ownerlock...>`)
independently confirmed the Keychain write succeeded.

### Crash reports, when something respring-loops

`/var/mobile/Library/Logs/CrashReporter/*.ips` -- `scp` the newest one back,
`Application Specific Information` + the crashing thread's frame list
(library names, even unsymbolicated, tell you a lot) are the first things to
read.

## 5. Known issue hit on this specific unit (not a toolchain problem)

The test device used for this session turned out to have iCloud Activation
Lock enabled from a previous owner (discovered via 3uTools' Batch
Activate/Erase screen, which will show a "Verify Apple ID" prompt if so).
This blocks Setup Assistant (`/Applications/Setup.app`) from ever completing,
which in turn seems to trigger a SpringBoard crash-loop
(`EXC_CRASH/SIGABRT`, deep in `FrontBoardServices`/`UIKitCore` scene-setup
code, unrelated to anything in this tweak) on every boot -- meaning the lock
overlay never actually got a chance to render on that unit, independent of
whether its own logic is correct. **This is specific to that one
Activation-Locked phone, not a bug in this project** -- a clean, fully
set-up device should not hit it. If you inherit a device in the same state:
Activation Lock can only be removed by the original account holder, Apple
Support with proof of purchase, or (for enterprise-owned/MDM-enrolled
devices) an official bypass code from whoever manages that MDM. There is no
legitimate SSH/plist trick around it, and none should be attempted.
