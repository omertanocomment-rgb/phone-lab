#!/usr/bin/env bash
#
# OMERTA iOS -- one-shot: boot Pongo via checkra1n, wait for the pongoOS
# USB device to enumerate, then push and load the omerta_boot module.
#
# Run this on a host with `checkra1n` installed and the iPhone 6 already
# sitting in DFU mode (check first with ../../tools/dfu/detect.sh).
#
# Usage:
#   ./boot_omerta.sh [path/to/Pongo.bin] [path/to/omerta_boot]
#
# Defaults assume you've downloaded the CI artifact into ../../output/
# and built the module locally.
#
set -euo pipefail

PONGO_BIN="${1:-../../output/Pongo.bin}"
MODULE_BIN="${2:-modules/omerta_boot/build/omerta_boot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$PONGO_BIN" ]]; then
    echo "Pongo binary not found at: $PONGO_BIN"
    echo "Download it from the GitHub Actions 'pongo-build' artifact first,"
    echo "or pass its path as the first argument."
    exit 1
fi

if [[ ! -f "$MODULE_BIN" ]]; then
    echo "omerta_boot module not found at: $MODULE_BIN"
    echo "Build it: (cd $SCRIPT_DIR/../modules/omerta_boot && make)"
    exit 1
fi

if ! command -v checkra1n >/dev/null 2>&1; then
    echo "checkra1n not found on PATH. Install it from https://checkra.in first."
    exit 1
fi

echo "== Booting Pongo via checkra1n -k $PONGO_BIN =="
checkra1n -k "$PONGO_BIN" &
CHECKRA1N_PID=$!

echo "== Waiting for pongoOS USB device (05ac:4141) to enumerate =="
FOUND=0
for i in $(seq 1 30); do
    if command -v lsusb >/dev/null 2>&1 && lsusb -d 05ac:4141 >/dev/null 2>&1; then
        FOUND=1
        break
    fi
    if command -v system_profiler >/dev/null 2>&1 && system_profiler SPUSBDataType 2>/dev/null | grep -qi "4141"; then
        FOUND=1
        break
    fi
    sleep 1
done

if [[ "$FOUND" -ne 1 ]]; then
    echo "Timed out waiting for pongoOS to enumerate on USB."
    echo "checkra1n may still be running (pid $CHECKRA1N_PID) -- check its window/output."
    exit 1
fi

echo "== pongoOS is up, pushing OMERTA module =="
python3 "$SCRIPT_DIR/omerta_load.py" "$MODULE_BIN"

echo
echo "Done. Open a serial/pongoterm session to the phone and run: omerta"
echo "(checkra1n is still running in the foreground as pid $CHECKRA1N_PID; Ctrl+C there when finished.)"
