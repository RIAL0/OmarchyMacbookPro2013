#!/bin/bash
#
# Download and install in one step, from a fresh Omarchy install:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/RIAL0/OmarchyMacbookPro2013/main/bootstrap.sh)
#
# That is process substitution, not a pipe. A plain `curl ... | bash` hands
# bash's stdin to the pipe, which breaks the sudo password prompt install.sh
# needs. `bash <( ... )` keeps your terminal attached, so it works.
#
# What this does: clones the repo to ~/.local/share/OmarchyMacbookPro2013
# (or pulls latest if it's already there), then runs its install.sh. Any
# arguments you pass go straight through, e.g.:
#
#   bash <(curl -fsSL .../bootstrap.sh) --no-widget
#
# Re-run the same command any time to update to the latest version and
# re-apply. See README.md in the repo for what install.sh actually does
# before running this on a machine you care about.
set -euo pipefail

REPO_URL="https://github.com/RIAL0/OmarchyMacbookPro2013.git"
DEST="${OMARCHY_MBP2013_DIR:-$HOME/.local/share/OmarchyMacbookPro2013}"

[[ -t 0 ]] || {
  echo "bootstrap: stdin isn't a terminal. Run with:" >&2
  echo "  bash <(curl -fsSL https://raw.githubusercontent.com/RIAL0/OmarchyMacbookPro2013/main/bootstrap.sh)" >&2
  echo "not 'curl ... | bash' — the pipe form breaks the sudo password prompt." >&2
  exit 1
}
command -v git >/dev/null || { echo "bootstrap: git is required. Install it first: sudo pacman -S git" >&2; exit 1; }
[[ -d /sys/firmware/efi/efivars ]] || { echo "bootstrap: not booted in EFI mode; this needs efivarfs." >&2; exit 1; }
grep -qi '^MacBook' /sys/class/dmi/id/product_name 2>/dev/null || {
  echo "bootstrap: this is for dual-GPU MacBook Pros with Apple gmux only" \
       "(detected: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown))." >&2
  exit 1
}

if [[ -d $DEST/.git ]]; then
  echo "==> $DEST already exists, pulling latest"
  git -C "$DEST" pull --ff-only
else
  echo "==> Cloning to $DEST"
  git clone --depth 1 "$REPO_URL" "$DEST"
fi

echo
exec "$DEST/install.sh" "$@"
