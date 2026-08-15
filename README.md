# Bongo Cat for Omarchy Quattro

![Bongo Cat](preview.png)

A lightweight native Quickshell plugin with no AUR package and no separate
`wayland-bongocat` process. Quickshell renders the cat while a small local C
helper emits only `L` or `R` paw events.

## Installation

```bash
omarchy plugin add https://github.com/HANCORE-linux/omarchy-bongocat.git --enable
```

## Controls

- Left-click the bar icon to open the settings panel.
- Right-click the bar icon to enable or disable Bongo Cat.
- Middle-click the bar icon to test the animation.
- Use the compact header buttons for enable, position lock, and animation test.
- Unlock and drag the cat to reposition it.
- While unlocked, use the mouse wheel to resize it and right-click to lock it.
- Set the width from 120 to 640 px.
- Choose `Default`, `Theme`, or a custom `#RRGGBB` color.
- In the open panel, press `P` to lock or unlock, `T` to test, or use the arrow
  keys to move an unlocked cat by 10 px.

## Keyboard access

Wayland intentionally provides no API that lets a passive overlay observe all
keyboard input. One explicit Polkit authorization is therefore required. The
`Allow Input` button installs this udev rule:

```udev
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
```

This grants keyboard-event access to the active local desktop user. It is more
limited than permanent membership in the `input` group, but it still means that
**every process running as the active user could read raw keyboard events**.
Access can be removed with `Revoke Input`, even while Bongo Cat is disabled.
This blocks new readers and restarts the Bongo Cat helper without access.
Processes that already hold an open device descriptor retain it until logout,
reboot, or device reconnection.

The plugin helper itself does not log characters or keycodes. It sends only
left-paw and right-paw events to Quickshell. Input-device access is still
security-sensitive and is never enabled automatically.

## Local build

On first load, the helper is compiled with the existing C compiler and stored
at:

```text
~/.cache/omarchy/bongocat/bongo-input
```

No AUR package is installed.

## Before removal

First select `Revoke Input` in the panel. Alternatively, run:

```bash
~/.config/omarchy/plugins/hancore.bongocat/helper/input-access remove
rm -rf ~/.cache/omarchy/bongocat
```

Then remove the plugin directory.

## Credits

The animation frames and paw mapping are derived from
`saatvik333/wayland-bongocat`. See `THIRD_PARTY.md` and
`LICENSE.wayland-bongocat`.
