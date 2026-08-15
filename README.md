# Bongo Cat for Omarchy Quattro

![Bongo Cat](preview.png)

A lightweight native Quickshell plugin with no AUR package and no separate
`wayland-bongocat` process. Quickshell renders the cat while the shipped local
C helper emits only `L` or `R` paw events.

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
- The lock prevents direct pointer dragging; panel position fields, arrows, and
  Reset remain available.
- Set the width from 120 to 640 px.
- Choose `Default`, `Theme`, or a custom `#RRGGBB` color.
- In the open panel, press `P` to lock or unlock, `T` to test, or use the arrow
  keys to move the cat by 10 px.

## Keyboard access

Wayland intentionally provides no API that lets a passive overlay observe all
keyboard input. `Allow Input` therefore requests explicit Polkit authorization
for the current Omarchy shell session.

The authorized launcher checks a root-owned runtime snapshot for changes made
during authorization and opens only selected keyboard devices. It then uses
`/usr/bin/setpriv` to discard the root UID, root GID, and all supplementary
groups before the helper is executed. The snapshot is unlinked before
execution. The unprivileged shipped helper then:

- reads only the inherited, read-only keyboard descriptors;
- binds its lifetime to `omarchy-shell`; and
- emits only `L` or `R` paw events, never characters or keycodes.

No udev rule, device ACL, `input` group membership, system service, or cleanup
hook is installed. `Revoke Input`, disabling or removing the plugin, a shell
exit, or a shell crash ends the helper and closes its keyboard descriptors.
Authorization must be granted again after a complete shell restart or login.
A newly connected keyboard requires `Rescan` and renewed authorization because
an unprivileged running helper cannot open additional event devices.

Raw input remains security-sensitive because the authorized helper necessarily
sees keyboard events internally. Access is never enabled automatically.

### Trust boundary

The plugin and runtime helper are owned by the desktop user. Polkit confirms the
authorization request, but it cannot authenticate those user-writable files. A
process already running as the same user could replace them before authorization
and receive the opened keyboard descriptors. Do not authorize input after a
suspected user-session compromise. Preventing this would require a persistent,
root-owned trust anchor, which this plugin intentionally does not install.

## Local build

The helper is compiled with the existing C compiler and stored for the current
login session at:

```text
$XDG_RUNTIME_DIR/omarchy/bongocat/bongo-input
```

The runtime directory is cleared automatically at logout. No AUR package is
installed.

## Removal

Use the normal Omarchy command:

```bash
omarchy plugin remove hancore.bongocat
```

Omarchy removes the bar entry from `shell.json` and deletes the plugin. The
session-scoped input helper exits automatically, so no privileged cleanup step
is required.

## Credits

The animation frames and paw mapping are derived from
`saatvik333/wayland-bongocat`. See `THIRD_PARTY.md` and
`LICENSE.wayland-bongocat`.
