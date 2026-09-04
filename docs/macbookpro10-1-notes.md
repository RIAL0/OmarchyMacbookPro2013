# Other MacBookPro10,1 notes for Omarchy

Things that came up while setting this laptop up, beyond the GPU. Useful as a reinstall
checklist.

## Wi-Fi

The Broadcom BCM4331 needs the proprietary `broadcom-wl` package (`omarchy pkg add broadcom-wl`).
It works, but it is unmaintained and prints two scary kernel WARNINGs on every boot:

- `Unpatched return thunk in use. This should not happen!` from `wl_module_init`
- `memcpy: detected field-spanning write ... wl_cfg80211_hybrid.c` from `wl_inform_single_bss`

Both come from the `wl` module, not from the GPU stack. Ignore them.

## Keyboard

`/etc/modprobe.d/hid_apple.conf`:

```
options hid_apple fnmode=2
```

makes F1 to F12 act as function keys by default, with `fn` for the media functions.

## Hardware cursor

With the NVIDIA card driving the panel, nouveau does not show the hardware cursor plane on this
GPU and the pointer is invisible. Workaround in `~/.config/hypr/looknfeel.lua`:

```lua
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})
```

Once you boot on the Intel GPU this is not needed and can be removed.

## Boot chain and hibernate

Omarchy installs Limine as the EFI boot loader. macOS stays bootable from its own EFI entry
(`efibootmgr` lists it). The kernel command line carries `resume=` and `resume_offset=` for a
swapfile on btrfs, so hibernate works. Hibernate resume goes through the firmware like a cold
boot, which is why the sleep hook exists.

The initramfs hooks are the stock Omarchy set:

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)
```

The `kms` hook is what loads `nouveau` and `i915` early. Do not blacklist nouveau; it will be
loaded anyway, and the gmux power-off needs it registered with vga_switcheroo.

## Battery, before and after

Rough numbers from a 60-second battery logger (whole-percent resolution) on 2026-09-04, active
desktop with a terminal session, 109 Wh pack as reported by upower:

| State | Drain |
|---|---|
| NVIDIA driving the panel | about 24 %/h, about 26 W |
| Intel driving the panel, NVIDIA idle at D0 | about 22 %/h, about 24 W |
| Intel driving the panel, NVIDIA powered off via gmux | about 20 %/h, about 21 W |

The last two windows were short (under ten minutes), so treat the differences as indicative.
An idle GT 650M at D0 is typically 4 to 6 W, which matches. Quiet moments on the Intel-only
configuration read around 16 W.

## Things that do not work

- `supergfxd` / `omarchy toggle hybrid-gpu`: see [how-it-works.md](how-it-works.md), dead ends.
- Runtime PM for nouveau on this Mac.
