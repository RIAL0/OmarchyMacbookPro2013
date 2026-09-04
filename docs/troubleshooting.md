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
- `od -An -tx1 -N4 /sys/bus/pci/devices/0000:01:00.0/config` printing `ff ff ff ff` means the
  rail really is cut, whatever `power_state` says. See the next section.

## "dGPU power" says "powered" after a plain suspend (lid close)

**Fixed in the status script on 2026-09-04; the card was never actually on.** If your copy of
`omarchy-gpu-switch` predates that, update it (re-run the installer). What really happens on a
deep suspend (`PM: suspend entry (deep)` in `journalctl -k`, the normal mode on this hardware):

1. The firmware wakes the machine with the NVIDIA card powered.
2. Early in resume the kernel's PCI core finds the card responding, marks it `D0` and restores
   its saved PCI config. That `D0` is what `/sys/bus/pci/devices/0000:01:00.0/power_state` shows
   from then on.
3. Later in the same resume `apple_gmux` cuts the card's power rail again (its resume handler
   re-applies `OFF` whenever the card was off before suspend). Nothing updates `power_state`.

So `vga_switcheroo`'s `Off`, the sleep hook's "dGPU already powered off", and the battery drain
were all right; only `power_state` was stale, and the old status script trusted it. The status
script now reads the PCI config space instead: with the rail cut every read returns `0xff`.
Check it by hand, no root needed:

```
od -An -tx1 -N4 /sys/bus/pci/devices/0000:01:00.0/config
```

`ff ff ff ff` means the card is off. Verified 2026-09-04 23:25 after a lid cycle: config space
all `ff`, `power_state` `D0`, switcheroo `Off`, battery draw unchanged. The NVRAM variable is
consumed on a plain suspend too (`efivarfs: removing variable gpu-power-prefs-...` at resume),
and the sleep hook re-writes it; check `journalctl -b | grep gpu-power-prefs`.

**The real limitation: `dgpu on` does not work after a suspend until you reboot.** Step 2 above
consumes nouveau's saved PCI state. When `ON` later re-powers the rail the card comes up with
blank BARs, nouveau has nothing to restore, and its first register access times out. Observed
on this GK107: about three dozen fault traces in six seconds (`g84_bar_flush` timeout, then
`nvkm_object_fini`, `gt215_pmu_init`, `nv50_runl_wait`, `gf119_disp_core_init`/`fini`), the
process that wrote `ON` killed with SIGKILL, and the desktop unaffected because Hyprland runs
entirely on the Intel side. The card is then in an unreliable driver state, and **the next
reboot ends on a kernel panic screen** (`Attempted to kill init! exitcode=0x00000009`: the same
oops fires inside PID 1 while it tears down devices for the reboot). Hold the power button; the
following boot is clean. This is a kernel-side quirk, not fixable from the scripts here.

So: if you need HDMI or DisplayPort and the machine has been suspended since boot, reboot first,
then `omarchy-gpu-switch dgpu on`. Do not write `ON` to `/sys/kernel/debug/vgaswitcheroo/switch`
by hand after a suspend. Re-issuing plain `OFF` when the switcheroo file already says `Off` is a
harmless no-op.

Untested idea for a real fix: a `pre` sleep hook that switches the card `ON` before suspend (from
a consistent off state nouveau's saved PCI state is intact, so the normal resume path works),
lets nouveau suspend and resume it itself, and switches it `OFF` again on `post`. Costs a second
or two of wake time and a powered card during suspend entry. PRs and reports welcome.

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
