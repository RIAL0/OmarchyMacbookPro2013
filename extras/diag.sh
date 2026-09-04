#!/bin/bash
# Diagnose the unreadable gpu-power-prefs variable, then reinstall the
# tolerant helper and restart the persist service. Run as root.
set -uo pipefail
cd "$(dirname "$0")"
(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }
V=/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9
LOG=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-gpu-switch-diag.log
exec > >(tee "$LOG") 2>&1

echo "== 1. current inode =="
stat -c 'size=%s' "$V" 2>&1; od -An -tx1 "$V" 2>&1

echo "== 2. delete and re-create =="
chattr -i "$V" 2>/dev/null; rm -f "$V"; echo "after rm exists: $([[ -e $V ]] && echo yes || echo no)"
printf '\x07\x00\x00\x00\x01\x00\x00\x00' > "$V"; echo "write exit=$?"
stat -c 'size=%s' "$V" 2>&1; od -An -tx1 "$V" 2>&1

echo "== 3. read through a fresh efivarfs mount =="
mkdir -p /run/efitest && mount -t efivarfs none /run/efitest && {
  ls /run/efitest | grep gpu-power
  od -An -tx1 /run/efitest/gpu-power-prefs-* 2>&1
  umount /run/efitest
}
rmdir /run/efitest 2>/dev/null

echo "== 4. write via efivar(1) =="
printf '\x01\x00\x00\x00' > /run/gpp.bin
efivar -n fa4ce28d-b62f-4c99-9cc3-6815686e30f9-gpu-power-prefs -w -f /run/gpp.bin -a 7 2>&1; echo "efivar exit=$?"
rm -f /run/gpp.bin
stat -c 'size=%s' "$V" 2>&1; od -An -tx1 "$V" 2>&1

echo "== 5. kernel messages =="
dmesg | grep -i efi | tail -5

echo "== 6. reinstall tolerant helper, restart service =="
install -Dm755 ../system/omarchy-gpu-switch-apply /usr/local/lib/omarchy-gpu-switch-apply
systemctl restart omarchy-gpu-switch-persist.service; echo "service exit=$?"
systemctl --no-pager status omarchy-gpu-switch-persist.service | head -4
echo
echo "Log saved to $LOG"
