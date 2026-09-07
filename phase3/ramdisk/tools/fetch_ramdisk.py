#!/usr/bin/env python3
#
# OMERTA iOS -- phase3 ramdisk sourcing
#
# Extracts the RestoreRamDisk component out of an Apple IPSW (a ZIP)
# and unwraps its IM4P (IMG4 payload) container to get the raw,
# directly-mountable Apple HFS+ image inside.
#
# Verified against a real iOS 12.5.8 (16H88) IPSW for iPhone7,2 (iPhone
# 6, this project's exact target -- see ../../PLAN.md): the
# "Customer Erase Install" RestoreRamDisk in this IPSW turned out to
# be UNENCRYPTED (no KBAG in its IM4P container -- confirmed via
# pyimg4, not assumed), so no device-specific or published firmware
# keys were needed at all. That may not hold for other iOS
# versions/devices; check payload.encrypted before assuming this
# script works unmodified elsewhere.
#
# Usage:
#   1. Get the exact-match IPSW for your target device/iOS version.
#      Confirm via `ideviceinfo -s | grep BuildVersion` on the real
#      device first -- api.ipsw.me/v4/device/<ProductType> lists
#      Apple's own signed URLs and checksums per version. Verify the
#      downloaded file's sha1sum against that before trusting it.
#   2. python3 fetch_ramdisk.py <path-to.ipsw> [output.dmg]
#      Lists BuildManifest.plist's RestoreRamDisk paths per variant if
#      run with just the IPSW path; pass a member path as arg 2 to
#      extract+unwrap that specific one.
#
import sys
import zipfile
import plistlib

try:
    import pyimg4
except ImportError:
    print("pyimg4 not installed: pip3 install pyimg4 --break-system-packages")
    sys.exit(1)


def list_ramdisks(ipsw_path):
    with zipfile.ZipFile(ipsw_path) as zf:
        with zf.open("BuildManifest.plist") as f:
            manifest = plistlib.load(f)
    print(f"ProductVersion: {manifest.get('ProductVersion')}")
    for bi in manifest["BuildIdentities"]:
        info = bi.get("Info", {})
        m = bi.get("Manifest", {})
        rd = m.get("RestoreRamDisk", {})
        path = rd.get("Info", {}).get("Path") if rd else None
        print(f"  {info.get('DeviceClass')} | {info.get('Variant')} -> {path}")


def extract_and_unwrap(ipsw_path, member, out_path):
    with zipfile.ZipFile(ipsw_path) as zf:
        wrapped = zf.read(member)
    im4p = pyimg4.IM4P(wrapped)
    print(f"fourcc={im4p.fourcc} encrypted={im4p.payload.encrypted} "
          f"compression={im4p.payload.compression}")
    if im4p.payload.encrypted:
        print("WARNING: payload is encrypted -- this script does not handle "
              "decryption. Look up the published key (theiphonewiki.com's "
              "Firmware Keys pages, if this device/version has one) and "
              "extend this script, don't guess.")
        sys.exit(1)
    raw = im4p.payload.output().data
    with open(out_path, "wb") as f:
        f.write(raw)
    print(f"Wrote {len(raw)} bytes to {out_path}")
    print("Sanity-check with: file " + out_path)
    print("(expect 'Apple HFS Plus Extended ... data (mounted)')")


def main():
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <ipsw-path> [member-path] [out.dmg]")
        sys.exit(1)
    ipsw_path = sys.argv[1]
    if len(sys.argv) == 2:
        list_ramdisks(ipsw_path)
        return
    member = sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else "RestoreRamDisk.raw.dmg"
    extract_and_unwrap(ipsw_path, member, out)


if __name__ == "__main__":
    main()
