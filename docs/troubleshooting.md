# Troubleshooting

## Black screen right after the firmware chime

The panel is on a GPU the kernel could not bring up. Hold `Cmd + Option + P + R` at power-on until
the chime sounds a second time. That resets NVRAM, which clears `gpu-power-prefs`, and the
firmware boots on the NVIDIA card. Because the mode file still says `integrated`, the helper will
write the variable again on that boot; run `omarchy-gpu-switch dedicated` before rebooting if you
want to stay on NVIDIA while investigating.

## Booted on the wrong GPU

```bash
omarchy-gpu-switch status
journalctl -b -u omarchy-gpu-switch-persist
```

The unit must show one of:

```
gpu-power-prefs set for next boot: integrated
gpu-power-prefs written for next boot: integrated (firmware refuses read-back this session)
```

Both are success. If the unit did not run at all, check its conditions:
`/etc/omarchy-gpu-mode` must exist and `/sys/firmware/efi/efivars` must be mounted
(`systemctl status omarchy-gpu-switch-persist` says which condition failed).

Exit code 3 means the NVRAM write itself failed. Try by hand as root:

```bash
V=/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9
chattr -i "$V"; printf '\x07\x00\x00\x00\x01\x00\x00\x00' > "$V"; echo $?
```

`extras/diag.sh` runs a fuller battery of NVRAM tests and logs them.

## Desktop does not start with the NVIDIA card powered off

Not seen on this setup, but the escape hatch is:

1. `Ctrl + Alt + F3`, log in.
2. `sudo /usr/local/lib/omarchy-gpu-switch-apply dgpu on`
3. `sudo reboot`

Then look at `~/.local/share/hyprland/hyprland.log` or `$XDG_RUNTIME_DIR/hypr/*/hyprland.log`.
The lines `Couldn't open device at /dev/dri/card0` and `Skipping device ... not a KMS device` are
normal; anything after that failing on card1 is the actual problem.

## "dGPU power" says "powered" instead of "powered off (gmux)"

- `cat /etc/omarchy-gpu-dgpu-power` should be `auto`. If it is `on`, you asked for that
  (`omarchy-gpu-switch dgpu off` to change back).
- `journalctl -b -u omarchy-gpu-switch-persist` should contain `dGPU powered off via gmux`.
  "vga_switcheroo has no discrete GPU client" means `apple_gmux` or `nouveau` was not up when the
  unit ran; check `lsmod`.
- `sudo cat /sys/kernel/debug/vgaswitcheroo/switch` shows the live state:
  `1:DIS: :Off:0000:01:00.0` is what you want.
- After a hibernate resume the sleep hook should have re-applied it:
  `journalctl -b | grep omarchy-gpu-switch-apply`.

## External display shows nothing

The HDMI and DisplayPort connectors are on the NVIDIA card. Run `omarchy-gpu-switch dgpu on`,
replug the cable, and configure the output in Hyprland. Whether Hyprland can drive an output on a
secondary GPU while the Intel GPU is primary is a Hyprland question, not a gmux one, and has not
been tested here. Booting `dedicated` is the sure way to use external displays.

## `od: Invalid argument` reading the variable

Expected after the firmware has consumed the variable in this power cycle. See quirk 2 in
[how-it-works.md](how-it-works.md). The write is still honoured.

## The bar widget is missing or shows "GPU"

- `omarchy-gpu-switch status --widget` must print something like
  `integrated|iGPU|Display on: ...`. If not, `~/.local/bin/omarchy-gpu-switch` is missing.
- `grep gpu-status ~/.config/omarchy/shell.json` must find the widget entry. If not:
  `omarchy bar put rial.gpu-status --before omarchy.power`.
- Editing the plugin does not replace the live widget; run `omarchy restart shell`.

## Reapplying after editing the helper

The unit is `RemainAfterExit`, so `systemctl enable --now` does nothing on a running system.
Use `sudo systemctl restart omarchy-gpu-switch-persist.service`, or just rerun `./install.sh`.
