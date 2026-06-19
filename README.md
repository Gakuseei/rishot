# rishot

A screenshot and annotation overlay for Wayland, built on [Quickshell](https://quickshell.outfoxxed.me/). Drag a region, click a window, or grab a whole monitor, mark it up, then copy, save, or upload it. rishot started as the screenshot surface inside my Hyprland rice, [Ricelin](https://github.com/Gakuseei/Ricelin), and now runs on its own.

## Compositor support

Capture works on any wlroots or Wayland compositor that speaks `wlr-screencopy` or `ext-image-copy-capture`. Wherever capture works, so do region selection, monitor selection, and every annotation tool. Window-click selection (click one window to grab just its frame) needs a per-compositor query, and rishot ships those for Hyprland, Sway, and Niri. Everywhere else it falls back to region and monitor selection.

| Compositor | Capture | Region + monitor | Window-click |
| ---------- | ------- | ---------------- | ------------ |
| Hyprland   | yes     | yes              | yes          |
| Sway       | yes     | yes              | yes          |
| Niri       | yes     | yes              | yes          |
| Wayfire    | yes     | yes              | no (region + monitor only) |
| COSMIC     | yes     | yes              | no (region + monitor only) |
| river      | yes     | yes              | no (region + monitor only) |

Any other wlroots compositor lands in the river row: capture plus region and monitor, no window-click.

## Features

- Region, window, and monitor capture
- Resize the selection after capture with corner and edge handles
- Tools: rectangle, ellipse, line, arrow, pen, highlighter, text, numbered steps, blur, pixelate, zoom
- Per-tool memory: each tool keeps its own colour and stroke width
- Undo and redo
- Copy to clipboard, save to disk, or upload
- A settings panel for pixelate coarseness, blur strength, zoom factor, and rebinding the key on Hyprland

## Install

### One-line installer

```sh
curl -fsSL https://raw.githubusercontent.com/Gakuseei/rishot/main/install.sh | sh
```

Read the script before you pipe it into a shell. To download, inspect, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/Gakuseei/rishot/main/install.sh -o install.sh
less install.sh
sh install.sh
```

The installer pulls runtime deps through your package manager where it can (pacman/yay/paru, apt, dnf, zypper, xbps; nix is detected but left to you), drops rishot into `~/.local/share/rishot`, and symlinks the launcher into `~/.local/bin`. It never touches your compositor config. It prints the keybind line for you to add. quickshell is in the official repos on Arch (extra), Fedora 44+, Void, and Debian sid / Ubuntu 26.10. On older Fedora it comes from the `errornointernet/quickshell` COPR, which a Qt version mismatch can sometimes break.

### Manual

```sh
git clone https://github.com/Gakuseei/rishot.git
cd rishot
bin/rishot
```

`bin/rishot` looks for its config dir in `$RISHOT_CONFIG_DIR`, then `~/.local/share/rishot/src`, `/usr/share/rishot/src`, `/usr/lib/rishot/src`, then `../src` next to the binary. Drop `src/` at any of those and put `rishot` on PATH.

## Dependencies

Required:

- `quickshell` (the `qs` binary)
- Qt 6: declarative, svg, 5compat, wayland
- `wl-clipboard`, for copy to clipboard

Optional:

- `imagemagick`: stitch a multi-monitor capture into one image
- `cliphist`: record copied shots into clipboard history
- `curl`: upload
- `kdialog`: native save-as dialog

## Running

```sh
rishot            # region: drag a box, or click a window to grab it
rishot monitor    # click a monitor to grab the whole output
```

From a checkout without installing, run `bin/rishot`.

## Keybinding

rishot does not grab a global hotkey for you. Bind the command yourself in your compositor config.

Hyprland (conf):

```
bind = , Print, exec, rishot
```

Hyprland (native Lua):

```lua
hl.bind("Print", hl.dsp.exec_cmd("rishot"))
```

Sway:

```
bindsym Print exec rishot
```

If you rebind from the in-app settings panel on Hyprland, the recorder checks whether your config is `hyprland.conf` or a native `hyprland.lua` and writes the matching form into its own include file, never your main config.

## Upload

Upload posts to `litterbox.catbox.moe` by default. The link it returns is unguessable but **public**, and it expires after 72 hours. It is not authenticated. Set `RISHOT_UPLOAD` to your own endpoint to use a different host. For anything sensitive, copy or save instead.

## Environment variables

- `RISHOT_CONFIG_DIR`: the Quickshell config dir (the one holding `shell.qml`)
- `RISHOT_SAVEDIR`: the auto-save directory
- `RISHOT_UPLOAD`: the upload endpoint (curl form-post target)
- `RISHOT_KEYBIND_FILE`: a keybind file rishot may write when you rebind from the settings panel

## Notes

Icon centring in the toolbar needs Qt 6.10 or newer. On older Qt the icons box-centre instead, a touch off, but everything works.
