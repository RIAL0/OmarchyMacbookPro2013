#!/bin/bash
# Remove everything install.sh put in place. Leaves NVRAM alone: the next
# boot will use whatever gpu-power-prefs currently holds, and after that the
# firmware default (dedicated GPU).
set -uo pipefail
(( EUID != 0 )) || { echo "Run as your normal user (it calls sudo itself)." >&2; exit 1; }

echo "==> System part (sudo)"
sudo bash -s <<'ROOT'
systemctl disable --now omarchy-gpu-switch-persist.service 2>/dev/null
rm -f /etc/systemd/system/omarchy-gpu-switch-persist.service \
      /usr/lib/systemd/system-sleep/omarchy-gpu-switch \
      /usr/local/lib/omarchy-gpu-switch-apply \
      /etc/omarchy-gpu-mode /etc/omarchy-gpu-dgpu-power /run/omarchy-gpu-dgpu-power
systemctl daemon-reload
# Give the dGPU its power back if we turned it off.
[[ -w /sys/kernel/debug/vgaswitcheroo/switch ]] && echo ON > /sys/kernel/debug/vgaswitcheroo/switch 2>/dev/null
ROOT

echo "==> User part"
rm -f "$HOME/.local/bin/omarchy-gpu-switch" "$HOME/.local/bin/omarchy-gpu-status"
rm -rf "$HOME/.config/omarchy/plugins/rial.gpu-status"
if command -v python3 >/dev/null && [[ -f $HOME/.config/omarchy/shell.json ]]; then
  python3 - "$HOME/.config/omarchy/shell.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
lay = d.get("bar", {}).get("layout", {})
for sec in lay.values():
    sec[:] = [w for w in sec if w.get("id") != "rial.gpu-status"]
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n")
PY
fi
omarchy restart shell >/dev/null 2>&1 || true
echo "Removed. Reboot to return to the firmware default GPU."
