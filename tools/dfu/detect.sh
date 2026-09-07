#!/usr/bin/env bash
#
# OMERTA iOS -- detect an iPhone 6 in normal, recovery, or DFU mode.
#
# Uses irecovery / ideviceinfo, the two tools your ios-tooling-builder
# project already produces for 32-bit Android/Termux (libirecovery +
# libimobiledevice). This script is deliberately dumb: it just tells you
# what state the phone is in, it doesn't drive it into DFU for you.
#
# Exact DFU button combo for the iPhone 6 (verified in
# ../../phase1/toolchain/01-jailbreak-iphone6-checkra1n.md against real
# hardware, iOS 12.5.8):
#   1. Connect the phone via USB.
#   2. Power the phone off completely.
#   3. Hold Power for 3 seconds.
#   4. Without releasing Power, also hold Home for 10 seconds.
#   5. Release Power only, keep holding Home for another ~5-10 seconds.
#   6. Screen stays completely black (no Apple logo, no "connect to
#      iTunes") -- that's DFU. Apple logo = held Power too long, redo from
#      step 2. "Connect to iTunes" = released Home too early (recovery
#      mode, not DFU), redo from step 2.
#
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

echo "== OMERTA iOS :: device state check =="

if ! have irecovery && ! have ideviceinfo; then
    echo "Neither 'irecovery' nor 'ideviceinfo' found on PATH."
    echo "These come from libirecovery / libimobiledevice -- see"
    echo "  ~/areas/ios-tooling-builder (irecovery, idevice_id, ideviceinfo)"
    echo "for how you already built these for this environment."
    exit 1
fi

echo
echo "-- Normal / lockdown mode (ideviceinfo) --"
if have ideviceinfo; then
    if ideviceinfo -s >/tmp/omerta_ideviceinfo.$$ 2>&1; then
        grep -E '^(DeviceClass|ProductType|ProductVersion|UniqueDeviceID)' /tmp/omerta_ideviceinfo.$$ || cat /tmp/omerta_ideviceinfo.$$
    else
        echo "No device responding in normal mode (expected if it's already in DFU/recovery)."
    fi
    rm -f /tmp/omerta_ideviceinfo.$$
else
    echo "ideviceinfo not available, skipping."
fi

echo
echo "-- Recovery / DFU mode (irecovery) --"
if have irecovery; then
    if irecovery -q >/tmp/omerta_irecovery.$$ 2>&1; then
        cat /tmp/omerta_irecovery.$$
        echo
        if grep -qi "MODE: DFU" /tmp/omerta_irecovery.$$; then
            echo "==> Phone IS in DFU mode. Ready for checkra1n -k / omerta_load.py."
        elif grep -qi "MODE: Recovery" /tmp/omerta_irecovery.$$; then
            echo "==> Phone is in Recovery mode, not DFU. checkra1n needs true DFU."
        fi
    else
        echo "No device responding in recovery/DFU mode."
    fi
    rm -f /tmp/omerta_irecovery.$$
else
    echo "irecovery not available, skipping."
fi

echo
echo "Expected chip identifier for iPhone 6 in DFU: CPID:8000 (Apple A8 / s8000)."
