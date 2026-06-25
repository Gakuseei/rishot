<div align="center">

<img src="assets/torii.svg" width="84" alt="rishot">

# rishot

**Screenshot and annotate, on Wayland**

[![license](https://img.shields.io/badge/License-MIT-e0563b?style=flat-square)](LICENSE)
&nbsp;![compositors](https://img.shields.io/badge/wlroots%20%C2%B7%20Niri%20%C2%B7%20KDE%20%C2%B7%20COSMIC-e0563b?style=flat-square)
&nbsp;![built on quickshell](https://img.shields.io/badge/Built%20on-Quickshell-3a4456?style=flat-square)

</div>

<div align="center">

![rishot demo](assets/demo.gif)

</div>

Drag a region, click a window, or grab a whole monitor. Mark it up, then copy, save, or upload. rishot started as the screenshot surface in my Hyprland rice, [Ricelin](https://github.com/Gakuseei/Ricelin), and now stands on its own.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Gakuseei/rishot/main/install.sh | sh
```

Bind a key (see [Keybinding](#keybinding)) and run `rishot`. The installer pulls deps through your package manager and never touches your compositor config.

<details><summary>Other ways to install</summary>

Inspect before you pipe:

```sh
curl -fsSL https://raw.githubusercontent.com/Gakuseei/rishot/main/install.sh -o install.sh
less install.sh
sh install.sh
```

From a checkout:

```sh
git clone https://github.com/Gakuseei/rishot.git
cd rishot
bin/rishot
```

Quickshell is in the official repos on Arch (extra), Fedora 44+, Void, and Debian sid / Ubuntu 26.10. Older Fedora pulls it from the `errornointernet/quickshell` COPR, which a Qt version mismatch can sometimes break. `bin/rishot` finds its `src/` via `$RISHOT_CONFIG_DIR`, then `~/.local/share/rishot/src`, `/usr/share/rishot/src`, `/usr/lib/rishot/src`, then `../src`.

</details>

## Features

- Region, window, and monitor capture
- Resize the selection after the fact with eight handles
- Twelve tools: rectangle, ellipse, line, arrow, pen, highlighter, text, numbered steps, blur, pixelate, zoom
- Rectangle and ellipse draw filled or outline, toggled with `f`
- Scroll while drawing to resize the stroke or text live
- Per-tool memory: each tool keeps its own colour, width and fill, saved across launches
- Undo and redo, copy, save, upload
- Save through a dialog or straight into a folder you pick, optionally copying to the clipboard at the same time
- Settings panel: pixelate coarseness, blur strength, zoom factor, save options, key rebind

## Compositors

|  | Capture | Region + monitor | Window-click |
| --- | --- | --- | --- |
| Hyprland | yes | yes | yes |
| Sway | yes | yes | yes |
| Niri | yes | yes | floating windows only |
| KDE Plasma (KWin) | yes | yes | no |
| Wayfire / COSMIC / river | yes | yes | region + monitor only |

Capture works on any wlroots or `ext-image-copy` compositor. KDE is the exception: KWin speaks no screencopy protocol, so there rishot grabs the desktop through `spectacle` instead (the installer pulls it in on KDE). Window-click, grabbing one window's frame, needs the compositor to tell rishot where each window sits. Hyprland and Sway do, Niri reports it for floating windows only, and KWin reports none, so on KDE you drag a region or grab a monitor.

## Keybinding

rishot does not grab a global hotkey. Bind it yourself:

```sh
bind = , Print, exec, rishot                       # Hyprland (conf)
hl.bind("Print", hl.dsp.exec_cmd("rishot"))        # Hyprland (lua)
bindsym Print exec rishot                          # Sway
```

Run `rishot` for region or window, `rishot monitor` for a whole output.

<details><summary>Dependencies</summary>

Required: `quickshell` (the `qs` binary), Qt 6 (declarative, svg, 5compat, wayland), `wl-clipboard`.

Optional: `imagemagick` (multi-monitor stitch), `cliphist` (clip history), `curl` (upload), `kdialog` (save dialog and folder picker), `libnotify` (a desktop notification when a shot is copied, saved or uploaded).

On KDE: `spectacle`, which rishot captures through since KWin has no screencopy protocol. The installer pulls it in when it sees a KDE session.

</details>

<details><summary>Environment variables</summary>

- `RISHOT_CONFIG_DIR`: the Quickshell config dir (the one holding `shell.qml`)
- `RISHOT_SAVEDIR`: the auto-save directory
- `RISHOT_CAPTURE`: force the capture backend, `screencopy` or `image` (otherwise picked per compositor)
- `RISHOT_UPLOAD`: the upload endpoint (curl form-post target)
- `RISHOT_KEYBIND_FILE`: file the rebind line is written into, taken as given (written verbatim, so point it at a dedicated include file)

Rebinding from the settings panel on Hyprland writes a matching conf or lua line into its own include file, never your main config.

</details>

<details><summary>Upload</summary>

Upload posts to `litterbox.catbox.moe` by default. The link it returns is unguessable but **public**, and it expires after 72 hours. When `imagemagick` is present rishot strips image metadata before sending. Set `RISHOT_UPLOAD` to use your own host. For anything sensitive, copy or save instead.

</details>

<details><summary>Notes</summary>

Toolbar icon centring needs Qt 6.10 or newer. On older Qt the icons box-centre, a touch off, but everything works.

</details>

---

<div align="center">
MIT &nbsp;·&nbsp; built with <a href="https://quickshell.outfoxxed.me/">Quickshell</a> &nbsp;·&nbsp; from <a href="https://github.com/Gakuseei/Ricelin">Ricelin</a>
</div>
