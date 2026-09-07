#!/usr/bin/env python3
#
# OMERTA iOS -- phase3: push the checkra1n KPF module + the patched
# RestoreRamDisk into an already-running Pongo shell over USB, then boot
# XNU from the pushed ramdisk instead of NAND.
#
# Same USB control-transfer protocol as phase2/tools/omerta_load.py
# (upstream checkra1n/PongoOS's module_load.py pattern): pongoOS enumerates
# as VID 0x05ac / PID 0x4141 and accepts a raw blob over EP2 bulk OUT,
# framed by two control transfers announcing the length, followed by a
# shell command sent as a third control transfer.
#
# Sequence (per phase3/README.md's "ramdisk/" section):
#   1. modload the KPF module (output/checkra1n-kpf-pongo)
#   2. push the patched ramdisk (output/RestoreRamDisk.patched.im4p) via
#      the `ramdisk` shell command
#   3. kpf_flags 1
#   4. bootx
#
# Fix applied here vs. the version that hung: the ramdisk file
# (91,709,466 bytes) is NOT a multiple of 512, so USB already ends that
# bulk transfer with a natural short packet -- do NOT send an extra
# unconditional zero-length write afterward, pongoOS isn't expecting it
# and it just hangs. Guard it like omerta_load.py already does for the
# KPF module.
#
# Usage:
#   1. Get DFU + a live pongoOS session first, e.g.:
#        sudo ./checkra1n/checkra1n -k output/Pongo.bin -E
#      (early-exit leaves the phone sitting in the Pongo shell over USB;
#      -E makes checkra1n itself return non-zero, so don't chain with &&
#      -- run this and the next command as two separate steps, checking
#      `lsusb` for 05ac:4141 in between)
#   2. Bump the USB bulk transfer size limit (Linux default is too small
#      for the ~92MB ramdisk):
#        echo 512 | sudo tee /sys/module/usbcore/parameters/usbfs_memory_mb
#   3. sudo python3 boot_patched_ramdisk.py \
#        output/checkra1n-kpf-pongo output/RestoreRamDisk.patched.im4p
#
import struct
import sys
import time

KPF_FLAGS = "1"

def push_blob(dev, data, label):
    print(f"[*] Pushing {label} ({len(data)} bytes)...")
    dev.ctrl_transfer(0x21, 2, 0, 0, 0)
    dev.ctrl_transfer(0x21, 1, 0, 0, struct.pack('I', len(data)))
    dev.write(2, data, 1000000)
    if len(data) % 512 == 0:
        dev.write(2, b"")
    print(f"[+] {label} pushed.")

def shell_cmd(dev, cmd):
    print(f"[*] Sending shell command: {cmd.strip()!r}")
    dev.ctrl_transfer(0x21, 3, 0, 0, cmd)

def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <kpf module path> <patched ramdisk path>")
        sys.exit(1)

    try:
        import usb.core
    except ImportError:
        print("pyusb not installed. Install it with: pip3 install pyusb")
        sys.exit(1)

    kpf_path, rdsk_path = sys.argv[1], sys.argv[2]
    kpf = open(kpf_path, "rb").read()
    rdsk = open(rdsk_path, "rb").read()

    dev = usb.core.find(idVendor=0x05ac, idProduct=0x4141)
    if dev is None:
        print("No pongoOS device found on USB (VID 0x05ac / PID 0x4141).")
        print("Make sure the phone is in DFU and you already ran:")
        print("  sudo ./checkra1n/checkra1n -k output/Pongo.bin -E")
        sys.exit(1)

    dev.set_configuration()

    push_blob(dev, kpf, "KPF module")
    shell_cmd(dev, "modload\n")
    time.sleep(0.5)

    push_blob(dev, rdsk, "patched ramdisk")
    shell_cmd(dev, "ramdisk\n")
    time.sleep(0.5)

    shell_cmd(dev, f"kpf_flags {KPF_FLAGS}\n")
    time.sleep(0.2)

    shell_cmd(dev, "bootx\n")

    print("[+] Sent modload + ramdisk + kpf_flags + bootx.")
    print("    Watch the device screen / serial console for boot progress.")

if __name__ == "__main__":
    main()
