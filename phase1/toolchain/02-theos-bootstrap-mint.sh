#!/usr/bin/env bash
# ==================================================================
# OMERTA -- Theos bootstrap for Linux Mint
#
# Installs Theos (the jailbreak-tweak build toolchain) plus an iOS
# SDK usable on Linux, so OMERTAiOS-tweak/ can actually be compiled
# on your Mint box. Confirmed against theos.dev's current Linux
# install docs and the theos/sdks repo.
#
# Run with: bash 02-theos-bootstrap-mint.sh
# ==================================================================
set -euo pipefail

echo "=========================================="
echo " OMERTA Theos bootstrap (Linux)"
echo "=========================================="

echo
echo "--- [1/4] Installing prerequisites ---"
sudo apt update
sudo apt install -y bash curl sudo git perl fakeroot dpkg-dev

echo
echo "--- [2/4] Installing Theos ---"
if [ -d "$HOME/theos" ]; then
  echo "\$HOME/theos already exists, skipping install-theos (will not overwrite)."
else
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
fi

export THEOS="$HOME/theos"

echo
echo "--- [3/4] Installing an iOS SDK (theos/sdks) ---"
SDK_TARGET="iPhoneOS12.4.sdk"
if [ -d "$THEOS/sdks/$SDK_TARGET" ]; then
  echo "$SDK_TARGET already present in \$THEOS/sdks/, skipping."
else
  TMP_SDKS="$HOME/.omerta-sdks-clone"
  rm -rf "$TMP_SDKS"
  git clone --depth=1 https://github.com/theos/sdks.git "$TMP_SDKS"
  mkdir -p "$THEOS/sdks"
  if [ -d "$TMP_SDKS/$SDK_TARGET" ]; then
    cp -r "$TMP_SDKS/$SDK_TARGET" "$THEOS/sdks/"
  else
    echo "Exact $SDK_TARGET not found in the repo -- copying every available"
    echo "iPhoneOS SDK instead so you can pick whichever exists:"
    cp -r "$TMP_SDKS"/iPhoneOS*.sdk "$THEOS/sdks/" 2>/dev/null || true
    ls "$THEOS/sdks/"
  fi
fi

echo
echo "--- [4/4] Persisting THEOS env var ---"
if ! grep -q 'export THEOS=' "$HOME/.bashrc" 2>/dev/null; then
  echo "export THEOS=\$HOME/theos" >> "$HOME/.bashrc"
  echo "export PATH=\$THEOS/bin:\$PATH" >> "$HOME/.bashrc"
  echo "Added THEOS env vars to ~/.bashrc -- run 'source ~/.bashrc' or open a new shell."
fi

echo
echo "=========================================="
echo " Done. Theos root: $THEOS"
echo " SDKs installed: $(ls "$THEOS/sdks" 2>/dev/null || echo none)"
echo
echo " Next: cd into OMERTAiOS-tweak/ and run:"
echo "   make package"
echo "=========================================="
