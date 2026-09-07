#!/usr/bin/env bash
# ==================================================================
# OMERTA iOS -- full headless install, scripted end-to-end
#
# This automates every step from the live debugging session in one
# shot: bootstrapping dpkg/apt/Sileo onto a checkra1n'd iPhone 6
# (iOS 12.5.8) with zero touchscreen interaction, installing
# LibHooker as the mobilesubstrate provider, and installing the
# OMERTAiOS-tweak package -- including automatic recovery from the
# two dpkg/apt bugs actually hit on the real device (a dpkg
# MaxLoopCount cycle, and the old apt binary segfaulting mid-upgrade).
#
# Prerequisites this script does NOT do for you:
#   - The phone must already be jailbroken via checkra1n and
#     reachable over an SSH tunnel (3uTools' USB tunnel, or your own
#     `iproxy 2222 22` -- either way you need a local port that
#     forwards to the phone's SSH on port 22).
#   - The phone needs its own Wi-Fi connection for the apt portion
#     (separate from the USB SSH tunnel).
#   - See toolchain/01-jailbreak-iphone6-checkra1n.md if the phone
#     isn't jailbroken yet.
#
# Usage:
#   ./install-omerta-ios.sh -p 2222 [options]
#
# Options:
#   -p, --port PORT       Local port your SSH tunnel forwards to the
#                          phone's port 22 (required).
#   -H, --host HOST       SSH host (default: 127.0.0.1 -- correct for
#                          almost every USB-tunnel setup).
#       --skip-bootstrap  Skip the Odyssey dpkg/apt/Sileo bootstrap
#                          (use if the phone already has dpkg/apt/Sileo
#                          installed -- the script checks for this
#                          automatically too, this flag just forces it).
#       --skip-pin-setup  Don't offer to set a temporary owner PIN
#                          after install (Phase 1 has no in-tweak UI
#                          for this yet -- see OMERTAiOS-tweak/README.md).
#       --ssh-key PATH    Also install this public key for passwordless
#                          SSH (skips the password prompt on every
#                          future connection). Generate one first with
#                          `ssh-keygen -t ed25519` if you don't have one.
#
# Safe to re-run: every step checks whether it's already done before
# doing it again.
# ==================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TWEAK_DIR="$SCRIPT_DIR/OMERTAiOS-tweak"
DEB_FILE="$TWEAK_DIR/packages/com.omerta.iosui_0.1.0_iphoneos-arm.deb"

PORT=""
HOST="127.0.0.1"
FORCE_BOOTSTRAP=0
SKIP_PIN_SETUP=0
SSH_KEY_PATH=""

usage() { sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port) PORT="$2"; shift 2 ;;
    -H|--host) HOST="$2"; shift 2 ;;
    --skip-bootstrap) FORCE_BOOTSTRAP=-1; shift ;;
    --skip-pin-setup) SKIP_PIN_SETUP=1; shift ;;
    --ssh-key) SSH_KEY_PATH="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done

if [[ -z "$PORT" ]]; then
  echo "ERROR: -p/--port is required (the local port your SSH tunnel maps to the phone's port 22)."
  usage 1
fi

SSH="ssh -o StrictHostKeyChecking=no -p $PORT root@$HOST"
SCP="scp -O -P $PORT"

log()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m!! $*\033[0m"; }
die()  { echo -e "\033[1;31mXX $*\033[0m"; exit 1; }

# ------------------------------------------------------------------
log "Checking SSH reachability on $HOST:$PORT..."
if ! $SSH -o ConnectTimeout=8 'echo ok' >/dev/null 2>&1; then
  die "Can't reach root@$HOST:$PORT over SSH. Confirm your tunnel is up (3uTools, or 'iproxy $PORT 22') and the phone is jailbroken/booted with checkra1n."
fi
echo "SSH reachable."

# ------------------------------------------------------------------
log "Checking whether dpkg/apt bootstrap is needed..."
HAS_DPKG=$($SSH 'command -v dpkg >/dev/null 2>&1 && echo yes || echo no')

if [[ "$HAS_DPKG" == "no" || $FORCE_BOOTSTRAP -eq 1 ]]; then
  log "Bootstrapping dpkg/apt/Sileo (Odyssey bootstrap)..."

  SAFETY=$($SSH 'ls /.bootstrapped /.installed_odyssey 2>/dev/null | wc -l')
  if [[ "$SAFETY" != "0" ]]; then
    die "This device already shows /.bootstrapped or /.installed_odyssey -- it looks like it was bootstrapped/migrated before. Re-running this could be destructive; stopping here. Investigate manually first."
  fi

  TMPDIR=$(mktemp -d)
  log "Downloading bootstrap files to $TMPDIR..."
  curl -fsSL -o "$TMPDIR/bootstrap_1500.tar.gz" \
    https://github.com/coolstar/Odyssey-bootstrap/raw/master/bootstrap_1500.tar.gz \
    || die "Failed to download bootstrap_1500.tar.gz"
  curl -fsSL -o "$TMPDIR/org.coolstar.sileo_2.3_iphoneos-arm.deb" \
    https://github.com/coolstar/Odyssey-bootstrap/raw/master/org.coolstar.sileo_2.3_iphoneos-arm.deb \
    || die "Failed to download Sileo .deb"
  curl -fsSL -o "$TMPDIR/procursus-deploy.sh" \
    https://raw.githubusercontent.com/coolstar/Odyssey-bootstrap/master/procursus-deploy-linux-macos.sh \
    || die "Failed to download procursus-deploy-linux-macos.sh"

  # Extract just the on-device install heredoc, not the whole wrapper
  # (the wrapper opens its own iproxy tunnel, which we don't want --
  # we're reusing the tunnel that's already up).
  START_LINE=$(grep -n 'cat << "EOF"' "$TMPDIR/procursus-deploy.sh" | head -1 | cut -d: -f1)
  END_LINE=$(awk -v s="$START_LINE" 'NR>s && /^EOF$/{print NR; exit}' "$TMPDIR/procursus-deploy.sh")
  if [[ -z "$START_LINE" || -z "$END_LINE" ]]; then
    die "Couldn't find the on-device install heredoc in procursus-deploy-linux-macos.sh -- the upstream script layout may have changed. Extract it manually (see toolchain/03-odyssey-bootstrap-and-headless-debug.md) and re-run with --skip-bootstrap once dpkg is present."
  fi
  sed -n "$((START_LINE+1)),$((END_LINE-1))p" "$TMPDIR/procursus-deploy.sh" > "$TMPDIR/odysseyra1n-install.bash"

  log "Copying bootstrap files to the phone..."
  $SCP "$TMPDIR/bootstrap_1500.tar.gz" "$TMPDIR/org.coolstar.sileo_2.3_iphoneos-arm.deb" "$TMPDIR/odysseyra1n-install.bash" \
    "root@$HOST:/var/root/" || die "scp of bootstrap files failed"

  log "Running the bootstrap install on-device (this takes a while)..."
  $SSH "cd /var/root && bash odysseyra1n-install.bash"
  BOOTSTRAP_RC=$?

  rm -rf "$TMPDIR"

  # The device regenerates /etc/ssh during bootstrap -- our next
  # connection will otherwise fail on a host-key mismatch.
  ssh-keygen -R "[$HOST]:$PORT" >/dev/null 2>&1 || true

  if [[ $BOOTSTRAP_RC -ne 0 ]]; then
    warn "Bootstrap script exited non-zero -- this is expected if it hit the known dpkg/apt issues below. Continuing to the recovery step."
  fi

  log "Retrying dist-upgrade with known-issue recovery..."
  # Gotcha #1: MaxLoopCount reached in SmartUnPack (a Pre-Depends
  # cycle dpkg's own cycle-breaker can't resolve on the first pass).
  # Fix: force the cached .deb straight in, bypassing apt's ordering.
  UPGRADE_OUT=$($SSH 'apt-get -o APT::Immediate-Configure=0 dist-upgrade -y --allow-downgrades --allow-unauthenticated 2>&1')
  if echo "$UPGRADE_OUT" | grep -qi 'MaxLoopCount'; then
    warn "Hit the known MaxLoopCount cycle -- forcing the blocking package in from cache and retrying."
    BLOCKER=$(echo "$UPGRADE_OUT" | grep -oP "SmartUnPack \(\d+\) for \K[^ ]+" | head -1)
    if [[ -n "$BLOCKER" ]]; then
      $SSH "dpkg -i --force-depends /var/cache/apt/archives/${BLOCKER}_*.deb"
    fi
    UPGRADE_OUT=$($SSH 'apt-get -o APT::Immediate-Configure=0 dist-upgrade -y --allow-downgrades --allow-unauthenticated 2>&1')
  fi
  # Gotcha #2: the device's old apt binary can segfault mid-upgrade
  # jumping many versions at once. Fix: force apt/libapt-pkg6.0 in
  # from cache first, then retry the full upgrade.
  if echo "$UPGRADE_OUT" | grep -qi 'Segmentation fault'; then
    warn "apt itself segfaulted -- forcing a newer apt/libapt-pkg6.0 in from cache and retrying."
    $SSH 'dpkg -i --force-depends /var/cache/apt/archives/libapt-pkg6.0_*.deb /var/cache/apt/archives/apt_*.deb'
    UPGRADE_OUT=$($SSH 'apt-get -o APT::Immediate-Configure=0 dist-upgrade -y --allow-downgrades --allow-unauthenticated -o Dpkg::Options::="--force-confnew" 2>&1')
  fi
  echo "$UPGRADE_OUT" | tail -20

  DPKG_OK=$($SSH 'command -v dpkg >/dev/null 2>&1 && echo yes || echo no')
  [[ "$DPKG_OK" == "yes" ]] || die "dpkg still isn't usable after bootstrap + recovery. Check manually over SSH -- see toolchain/03-odyssey-bootstrap-and-headless-debug.md for the troubleshooting steps this script automates."
  log "dpkg/apt bootstrap complete."
else
  echo "dpkg already present -- skipping bootstrap."
fi

# ------------------------------------------------------------------
log "Checking for a mobilesubstrate provider (LibHooker)..."
HAS_SUBSTRATE=$($SSH "dpkg -l 2>/dev/null | grep -q '^ii.*org.coolstar.libhooker' && echo yes || echo no")
if [[ "$HAS_SUBSTRATE" == "no" ]]; then
  log "Installing org.coolstar.libhooker..."
  $SSH 'apt-get install -y --allow-unauthenticated org.coolstar.libhooker' \
    || die "Failed to install libhooker. Check 'apt-cache search substrate' on-device for what's actually available in your sources."
else
  echo "libhooker already installed."
fi

# ------------------------------------------------------------------
log "Checking the device's dpkg architecture convention..."
DEVICE_ARCH=$($SSH "dpkg --print-architecture 2>/dev/null")
echo "Device reports: $DEVICE_ARCH"
if [[ "$DEVICE_ARCH" != "iphoneos-arm" ]]; then
  warn "Device architecture is '$DEVICE_ARCH', not the 'iphoneos-arm' this .deb is tagged for."
  warn "If the install below fails on a dependency error, see toolchain/03-odyssey-bootstrap-and-headless-debug.md section 3 -- you likely need to repackage OMERTAiOS-tweak/control for this device's actual tag and 'make package' again."
fi

# ------------------------------------------------------------------
if [[ ! -f "$DEB_FILE" ]]; then
  if [[ -n "${THEOS:-}" ]] && command -v make >/dev/null 2>&1; then
    log "No prebuilt .deb found -- building from source with Theos..."
    ( cd "$TWEAK_DIR" && make package FINALPACKAGE=1 ) || die "Build failed. Check that \$THEOS and an iOS SDK are installed (toolchain/02-theos-bootstrap-mint.sh)."
  else
    die "No prebuilt .deb at $DEB_FILE and \$THEOS isn't set to build one. Either install Theos (toolchain/02-theos-bootstrap-mint.sh) or use the prebuilt .deb shipped in this project."
  fi
fi

log "Installing OMERTAiOS-tweak ($(basename "$DEB_FILE"))..."
$SCP "$DEB_FILE" "root@$HOST:/var/mobile/" || die "scp of the tweak .deb failed"
INSTALL_OUT=$($SSH "dpkg -i /var/mobile/$(basename "$DEB_FILE") 2>&1")
echo "$INSTALL_OUT"
if echo "$INSTALL_OUT" | grep -qi 'dependency problems'; then
  die "Install failed on a dependency problem -- almost always the architecture-tag mismatch described above. See toolchain/03-odyssey-bootstrap-and-headless-debug.md section 3."
fi

# ------------------------------------------------------------------
if [[ -n "$SSH_KEY_PATH" ]]; then
  if [[ -f "$SSH_KEY_PATH" ]]; then
    log "Installing SSH public key for passwordless login..."
    PUBKEY=$(cat "$SSH_KEY_PATH")
    $SSH "mkdir -p /var/root/.ssh && chmod 700 /var/root/.ssh && echo '$PUBKEY' >> /var/root/.ssh/authorized_keys && chmod 600 /var/root/.ssh/authorized_keys"
    echo "Done -- future connections to root@$HOST:$PORT with the matching private key won't prompt for a password."
  else
    warn "SSH key '$SSH_KEY_PATH' not found -- skipping passwordless setup."
  fi
fi

# ------------------------------------------------------------------
if [[ $SKIP_PIN_SETUP -eq 0 ]]; then
  echo
  read -p "Set a temporary owner PIN now so you can test the lock screen? [y/N] " SETPIN
  if [[ "$SETPIN" =~ ^[Yy]$ ]]; then
    read -p "Enter a PIN to test with (digits only): " TESTPIN
    log "Setting a temporary constructor to write the PIN, rebuilding, reinstalling..."
    TMP_CTOR=$(mktemp)
    cat > "$TMP_CTOR" <<EOF
%ctor { [OMOwnerLock setOwnerPin:@"$TESTPIN"]; }
EOF
    # Insert the ctor into a scratch copy of Tweak.xm, build, install, remove.
    SCRATCH="$TWEAK_DIR/Tweak.xm.pinsetup.bak"
    cp "$TWEAK_DIR/Tweak.xm" "$SCRATCH"
    awk -v ctor="$(cat "$TMP_CTOR")" '
      /%hook SpringBoard/ && !done { print; print ctor; done=1; next }
      { print }
    ' "$SCRATCH" > "$TWEAK_DIR/Tweak.xm"
    rm -f "$TMP_CTOR"
    ( cd "$TWEAK_DIR" && make package FINALPACKAGE=1 ) && \
      $SCP "$TWEAK_DIR"/packages/com.omerta.iosui_0.1.0_iphoneos-arm.deb "root@$HOST:/var/mobile/" && \
      $SSH "dpkg -i /var/mobile/com.omerta.iosui_0.1.0_iphoneos-arm.deb"
    mv "$SCRATCH" "$TWEAK_DIR/Tweak.xm"   # restore the clean version
    log "PIN set to '$TESTPIN' and reinstalled with the clean (no-hardcoded-PIN) source restored."
    warn "Remember: this PIN is only in the Keychain on the device now, not in the source. To clear it, reinstall the plain package again after uninstalling, or add a one-off 'setOwnerPin' call for a new PIN the same way."
  fi
fi

# ------------------------------------------------------------------
log "Respringing SpringBoard to activate the tweak..."
$SSH 'killall -9 SpringBoard'

log "Done."
echo "If the phone's screen works, you should see the lock overlay (if a PIN was set) after the respring."
echo "If it doesn't (broken screen, or you just want to confirm the tweak is actually running), verify"
echo "over SSH instead -- see toolchain/03-odyssey-bootstrap-and-headless-debug.md section 4 for the"
echo "syslog/screenshot/crash-report techniques used to validate this without ever touching the screen."
