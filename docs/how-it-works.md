# How it works

## The hardware

MacBookPro10,1: Intel HD 4000 (`i915`, PCI 0000:00:02.0) and NVIDIA GeForce GT 650M Mac Edition
(`nouveau`, PCI 0000:01:00.0). A small Apple controller called **gmux** (`apple_gmux` in the
kernel) sits between the two GPUs and the panel. It decides which GPU's output reaches the
built-in display and can cut power to the discrete card. The kernel exposes gmux through
`vga_switcheroo` (`/sys/kernel/debug/vgaswitcheroo/switch`).

The three external outputs (HDMI, two Thunderbolt/DisplayPort) are wired to the NVIDIA card only.

## Who owns the panel is decided by the firmware

At power-on the Boot ROM reads the EFI variable

```
gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9
```

and programs gmux accordingly, before any OS runs. This is the mechanism
[0xbb/gpu-switch](https://github.com/0xbb/gpu-switch) uses.

| data byte 0 | meaning |
|---|---|
| `01` | integrated (Intel) |
| `00` | dedicated (NVIDIA) |
| variable absent | dedicated (firmware default) |

Writing it through efivarfs: 4 attribute bytes `07 00 00 00` (non-volatile, boot service, runtime),
then 4 data bytes. The file is immutable by default; `chattr -i` first. A reboot is required.

`gpu-policy-7c436110-...` (Apple's own NVRAM GUID) is a different, macOS-side variable and is not
what the firmware reads for this.

## Quirk 1: the variable is one-shot

The firmware **deletes the variable after honouring it**. Verified: written `=01`, reboot, Intel
boot, variable gone from efivarfs. So a single write, as `gpu-switch` does, only lasts one boot.
The next boot silently falls back to the NVIDIA card.

That is why the chosen mode lives in `/etc/omarchy-gpu-mode` and the helper re-writes the
variable on **every** boot (systemd unit) and after hibernate resume (sleep hook).

## Quirk 2: after consumption, the variable cannot be read back

In a session where the firmware consumed the variable at power-on, re-creating it works
(SetVariable succeeds, efivarfs shows a 4-byte inode) but every GetVariable returns
`EFI_INVALID_PARAMETER`: `od` prints `Invalid argument`. Deleting and re-writing, or mounting a
fresh efivarfs, does not help. In a session where nothing was consumed at power-on, the same
write reads back fine.

Verified that **an unreadable write is still honoured**: the helper wrote the variable with
"firmware refuses read-back", and the next boot came up on the Intel GPU. So the helper treats
"written but unreadable" as success and only fails if the write itself fails or the inode vanishes.
Never treat `od: Invalid argument` on this variable as an error, and never use the variable's
presence or readability as state. Use the mode file and the kernel log instead.

## Powering the idle NVIDIA card off

On an Intel boot nouveau leaves the GT 650M fully powered at D0. There is no runtime PM on Macs
(`nouveau.runpm` does not help). gmux can cut its rail:

```
echo OFF > /sys/kernel/debug/vgaswitcheroo/switch      # root, debugfs
```

The kernel logs `VGA switcheroo: switched nouveau off` and the PCI device reads
`power_state = D3hot` (its HDMI audio function goes to D3cold). Verified live with Hyprland and
Xwayland holding `/dev/dri/card0` open: no hiccup.

The helper does this at boot with the systemd unit ordered `Before=display-manager.service
sddm.service`, so the card is already off when the compositor enumerates DRM devices. Opening a
switcheroo-off card fails with EINVAL; aquamarine (Hyprland's backend) logs
`libseat: Couldn't open device at /dev/dri/card0` and `Skipping device ... not a KMS device`, then
starts on card1 (i915). Those two error lines are expected.

The card is never touched while it drives the panel.

## Boot signatures

Check with `journalctl -b -k`.

| | NVIDIA boot | Intel boot |
|---|---|---|
| framebuffer | `fbcon: nouveaudrmfb (fb0) is primary device` | `fbcon: i915drmfb (fb0) is primary device` |
| panel | eDP on the nouveau card | `card1-eDP-1` connected on 0000:00:02.0 |
| other driver | i915: "failed to retrieve link info, disabling eDP", phantom `VGA-1` | nouveau: "Cannot find any crtc or sizes" (harmless) |

i915's "Failed to find VBIOS tables (VBT)" and "Invalid PCI ROM header" appear on every boot with
either GPU and mean nothing.

## Verification timeline (2026-09-04)

- 15:53 boot: NVIDIA (firmware default). Baseline.
- Variable written `=01` at 17:50:56, reboot.
- 17:52 boot: Intel. Variable gone from efivarfs (quirk 1). Re-write succeeds but is unreadable
  (quirk 2). Helper and unit installed at 18:18.
- 18:28 boot: Intel, from an unreadable write. Quirk 2 resolved: unreadable writes are honoured.
  dGPU power-off added at 18:44 and tested live.
- 18:52 boot: Intel. Unit ran at 18:52:06.75, sddm started at 18:52:06.76. Card off before the
  compositor, Hyprland skipped card0 cleanly, `power_state` D3hot.

## Dead ends

- **supergfxd / `omarchy toggle hybrid-gpu`**: logs `DiscreetGpu::new: no devices??` and always
  reports "Integrated". It cannot see through gmux. It also drops an ineffective
  `blacklist nouveau` in `/etc/modprobe.d/supergfxd.conf` (nouveau is force-loaded by the
  mkinitcpio `kms` hook anyway). Uninstall it and remove that file.
- **`nouveau.runpm`, PCI runtime PM**: not wired up on Macs. `power/runtime_status` says nothing
  useful; read `power_state` instead.
- **`apple_set_os`**: only needed on MacBookPro11,3 / 11,5.
