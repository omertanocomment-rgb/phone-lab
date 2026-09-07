#!/usr/bin/env bash
#
# OMERTA iOS -- detect an iPhone 6 in normal, recovery, or DFU mode.
#
# Uses irecovery / ideviceinfo, the two tools your ios-tooling-builder
# project already produces for 32-bit Android/Termux (libirecovery +
# libimobiledevice). This script is deliberately dumb: it just tells you
# what state the phone is in, it doesn't drive it into DFU for you --
# that's a manual button-combo step on the iPhone 6 (hold Power+Home,
# release Power after ~10s while keeping Home, until the screen stays
# black -- get the exact timing from phase1/toolchain/01-jailbreak-iphone6-checkra1n.md
# once that's merged in, rather than trusting a generic number here).
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
