#!/usr/bin/env python3
#
# OMERTA iOS -- push the omerta_boot module into an already-running Pongo
# shell over USB and run it.
#
# Adapted from upstream checkra1n/PongoOS's scripts/module_load.py (same
# USB control-transfer protocol: pongoOS enumerates as VID 0x05ac /
# PID 0x4141 and accepts a raw Mach-O module load over EP2, followed by
# the `modload` shell command). Requires pyusb (`pip install pyusb`, plus
# a libusb backend -- on Linux that's usually already present via
# libusb-1.0-0).
#
# Usage:
#   1. Get the phone into DFU and boot Pongo first, e.g.:
#        checkra1n -k output/Pongo.bin
#      (this leaves the phone sitting in the Pongo shell over USB)
#   2. Build the module: `cd phase2/modules/omerta_boot && make`
#   3. python3 omerta_load.py ../modules/omerta_boot/build/omerta_boot
#   4. In the Pongo shell (serial/pongoterm), run: omerta
#
import struct
import sys

def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path to omerta_boot module binary>")
        print("  build it first: cd phase2/modules/omerta_boot && make")
        sys.exit(1)

    try:
        import usb.core
    except ImportError:
        print("pyusb not installed. Install it with: pip3 install pyusb")
        sys.exit(1)

    data = open(sys.argv[1], "rb").read()

    dev = usb.core.find(idVendor=0x05ac, idProduct=0x4141)
    if dev is None:
        print("No pongoOS device found on USB (VID 0x05ac / PID 0x4141).")
        print("Make sure the phone is in DFU and you already ran:")
        print("  checkra1n -k <Pongo.bin or PongoConsolidated.bin>")
        sys.exit(1)

    dev.set_configuration()

    # Same three-transfer handshake pongoOS's own module_load.py uses:
    # announce a data-in transfer, tell it the length, then stream the
    # module bytes over the bulk OUT endpoint.
    dev.ctrl_transfer(0x21, 2, 0, 0, 0)
    dev.ctrl_transfer(0x21, 1, 0, 0, struct.pack('I', len(data)))
    dev.write(2, data, 100000)
    if len(data) % 512 == 0:
        dev.write(2, b"")

    # Tell the Pongo shell to load what we just streamed in.
    dev.ctrl_transfer(0x21, 3, 0, 0, "modload\n")

    print(f"Pushed {sys.argv[1]} ({len(data)} bytes) and sent 'modload'.")
    print("Run `omerta` in the Pongo shell to see the boot status banner.")

if __name__ == "__main__":
    main()
