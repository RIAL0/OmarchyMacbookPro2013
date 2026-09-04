#!/bin/bash
#
# Install GPU switching + idle dGPU power-off for a dual-GPU MacBook Pro
# (Apple gmux, e.g. MacBookPro10,1) running Omarchy.
#
# Run as your normal user from a real terminal (sudo will ask for your
# password for the system part):
#
#   ./install.sh
#
# What it does:
#   system (via sudo)
#     /usr/local/lib/omarchy-gpu-switch-apply          root helper
#     /etc/systemd/system/omarchy-gpu-switch-persist.service   runs it every boot
#     /usr/lib/systemd/system-sleep/omarchy-gpu-switch  re-runs it after hibernate
#     /etc/omarchy-gpu-mode                             seeded from the current panel owner
#     /etc/omarchy-gpu-dgpu-power                       "auto" (power the idle dGPU off)
#   user
#     ~/.local/bin/omarchy-gpu-switch                   CLI + interactive switcher
#     ~/.config/omarchy/plugins/rial.gpu-status/        bar widget (iGPU / dGPU)
#     shell.json                                        widget placed before omarchy.power
#
# Options:
#   --no-widget     skip the bar widget
#   --system-only   only the root pieces (no CLI, no widget)
set -euo pipefail
cd "$(dirname "$0")"

WIDGET=1; USER_PART=1
for a in "$@"; do
  case $a in
    --no-widget)   WIDGET=0 ;;
    --system-only) USER_PART=0; WIDGET=0 ;;
    -h|--help)     sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

(( EUID != 0 )) || { echo "Run this as your normal user, not with sudo (it calls sudo itself)." >&2; exit 1; }
[[ -t 0 ]] || { echo "Needs an interactive terminal (sudo password prompt)." >&2; exit 1; }
[[ -d /sys/firmware/efi/efivars ]] || { echo "Not booted in EFI mode; gpu-power-prefs needs efivarfs." >&2; exit 1; }
grep -qi '^MacBook' /sys/class/dmi/id/product_name 2>/dev/null \
  || { echo "This is for dual-GPU MacBook Pros with Apple gmux only." >&2; exit 1; }
grep -q apple_gmux /proc/modules 2>/dev/null || [[ -d /sys/module/apple_gmux ]] \
  || echo "warning: apple_gmux is not loaded; the dGPU power-off step will be skipped until it is." >&2

echo "==> System part (sudo)"
sudo bash -s <<'ROOT'
set -euo pipefail
install -Dm755 system/omarchy-gpu-switch-apply /usr/local/lib/omarchy-gpu-switch-apply
install -Dm644 system/omarchy-gpu-switch-persist.service /etc/systemd/system/omarchy-gpu-switch-persist.service
install -Dm755 system/omarchy-gpu-switch.sleep-hook /usr/lib/systemd/system-sleep/omarchy-gpu-switch

# Seed the mode from whatever drives the panel right now, unless already set.
if [[ ! -e /etc/omarchy-gpu-mode ]]; then
  mode=dedicated
  for c in /sys/class/drm/card*-eDP-*; do
    [[ -r $c/status && $(<"$c/status") == connected ]] || continue
    [[ $(<"$(readlink -f "$c/device/device")/vendor") == 0x8086 ]] && mode=integrated
  done
  printf '%s\n' "$mode" > /etc/omarchy-gpu-mode
  echo "Seeded /etc/omarchy-gpu-mode = $mode"
fi
[[ -e /etc/omarchy-gpu-dgpu-power ]] || printf 'auto\n' > /etc/omarchy-gpu-dgpu-power

systemctl daemon-reload
systemctl enable omarchy-gpu-switch-persist.service
# restart, not "enable --now": the unit is RemainAfterExit and must re-run now.
systemctl restart omarchy-gpu-switch-persist.service
systemctl --no-pager --lines=4 status omarchy-gpu-switch-persist.service || true
ROOT

if (( USER_PART )); then
  echo "==> User CLI"
  install -Dm755 user/omarchy-gpu-switch "$HOME/.local/bin/omarchy-gpu-switch"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "note: ~/.local/bin is not on your PATH" ;; esac
fi

if (( WIDGET )); then
  echo "==> Bar widget"
  dest="$HOME/.config/omarchy/plugins/rial.gpu-status"
  install -Dm644 user/plugins/rial.gpu-status/GpuStatus.qml "$dest/GpuStatus.qml"
  install -Dm644 user/plugins/rial.gpu-status/manifest.json "$dest/manifest.json"
  if grep -q '"rial.gpu-status"' "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
    echo "widget already in shell.json"
  else
    omarchy bar put rial.gpu-status --before omarchy.power \
      || omarchy bar put rial.gpu-status --section right
  fi
  omarchy restart shell >/dev/null 2>&1 || true
fi

echo
echo "==> Done. Current state:"
"$HOME/.local/bin/omarchy-gpu-switch" status 2>/dev/null || /usr/local/lib/omarchy-gpu-switch-apply
echo
echo "To boot on the Intel GPU:  omarchy-gpu-switch integrated   (then reboot)"
