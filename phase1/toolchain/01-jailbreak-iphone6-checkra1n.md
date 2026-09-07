# Jailbreaking the iPhone 6 (iOS 12.5.8) from Linux Mint via checkra1n

This is a procedure, not a script — putting the phone into DFU mode needs
precisely-timed physical button presses, which nothing running on your Mint
box can automate for you.

**Confirmed compatible:** checkra1n supports iPhone 5s through iPhone X
(the iPhone 6/A8 falls inside that range) and ships a Linux build; the only
Linux-side exclusion is A7 devices, which doesn't apply to your A8 iPhone 6.
`palera1n` is NOT usable here — it requires iOS/iPadOS 15+, and this phone
tops out at iOS 12. (Source: checkra.in, palera1n GitHub.)

**Important:** checkra1n's jailbreak is semi-tethered. Every time the phone
reboots (including if the battery dies), you lose the jailbreak and must
redo the DFU + checkra1n steps below to get back into it.

## 1. Get checkra1n on Linux Mint

```bash
mkdir -p ~/checkra1n && cd ~/checkra1n
wget -O checkra1n https://assets.checkra.in/downloads/linux/cli/x86_64/0.12.4/checkra1n
chmod +x checkra1n
```

If that exact version 404s, grab the current Linux CLI build URL from
https://checkra.in/ (Download > Linux) and substitute it above — the tool
updates its own hosted build periodically.

## 2. Back up first

Do this before anything else. Plug the iPhone 6 in normally (not DFU yet)
and, in the Finder/whatever tool you use for iOS backups, take a full
encrypted backup. Jailbreaking carries real risk of a bad boot cycle; don't
skip this.

## 3. Put the iPhone 6 into DFU mode

The iPhone 6 uses the older (pre-Face-ID) button combo:

1. Connect the iPhone 6 to the Mint box via USB.
2. Power the phone off completely.
3. Hold **Power** for 3 seconds.
4. Without releasing Power, also hold **Home** for 10 seconds.
5. Release **Power** only, keep holding **Home** for another ~5-10 seconds.
6. The screen should stay completely black (no Apple logo, no "connect to
   iTunes" screen) — that's DFU mode. If you see the Apple logo, you held
   Power too long and started a normal boot; if you see "connect to iTunes",
   you released Home too early and landed in recovery mode instead. Redo
   from step 2 either way.

## 4. Run checkra1n

```bash
cd ~/checkra1n
sudo ./checkra1n
```

Follow its on-screen instructions — it will detect the phone in DFU mode,
exploit the bootrom (checkm8), and walk it through to a jailbroken boot.
When it finishes, the phone boots normally with the checkra1n app icon on
the home screen.

## 5. Verify

- The phone should have a "checkra1n" app on the home screen.
- Open it; it should offer to install a package manager (Sileo is the
  modern standard — pick that over Cydia/Zebra if given the choice).
- Once Sileo/Cydia is installed and launches, the jailbreak is confirmed
  working, and the phone is ready for Theos-built tweaks to be installed
  onto it (via `.deb` file transfer + `dpkg -i`, or Sileo's own file import).

## Getting tweaks onto the phone from here

Once `OMERTAiOS-tweak` is built on the Mint box (`make package`, see the
Theos bootstrap script and the tweak's own README), the resulting `.deb` in
`packages/` needs to get onto the phone and installed. Two practical paths
once the jailbreak is confirmed:

```bash
# with the phone jailbroken, on the same wifi network, over SSH
# (OpenSSH is available in Sileo/Cydia -- install it there first)
scp packages/com.omerta.iosui_0.1.0_iphoneos-arm64.deb root@<phone-ip>:/var/mobile/
ssh root@<phone-ip> "dpkg -i /var/mobile/com.omerta.iosui_0.1.0_iphoneos-arm64.deb; killall -9 SpringBoard"
```

Default jailbreak root password is usually `alpine` — change it immediately
via `passwd` over SSH once you've confirmed access, since the phone is now
reachable over the network with a well-known default credential.
