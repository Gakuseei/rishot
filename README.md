# rishot

A Wayland screenshot and annotation overlay built on [Quickshell](https://quickshell.outfoxxed.me/). You drag a region (or click a window or monitor), annotate it, and copy, save, or upload the result. rishot grew out of the screenshot surface of the [Ricelin](https://github.com/Gakuseei/Ricelin) Hyprland rice and is being pulled out into a standalone tool.

## Status

Early standalone extraction, work in progress. The core capture and annotation paths work; some pieces are still Hyprland-specific and packaging is not done yet.

## Compositor support

Capture works on any wlroots or Wayland compositor that implements `wlr-screencopy` or `ext-image-copy-capture`. That covers Hyprland, Sway, river, Wayfire, Niri, and COSMIC, among others.

Region selection, monitor selection, and the full annotation toolset work everywhere. Window-click selection (click a single window to grab just its frame) is currently Hyprland only; a multi-compositor adapter is upcoming.

## Dependencies

Required:

- `quickshell` (the `qs` binary)
- Qt 6: declarative, svg, 5compat, wayland
- `wl-clipboard` (`wl-copy`), for copy-to-clipboard

Optional:

- `imagemagick` — stitching a multi-monitor capture into one image
- `cliphist` — recording copied shots into clipboard history
- `curl` — uploading
- `kdialog` — the save-as file dialog

## Running

Run from the repo:

```sh
bin/rishot            # region: drag a box, or click a window to grab it
bin/rishot monitor    # click a monitor to grab the whole output
```

rishot does not register a global hotkey for you. Bind the command to a key in your compositor config yourself.

Hyprland:

```
bind = , Print, exec, rishot
```

Sway:

```
bindsym Print exec rishot
```

Install via the AUR or an installer is coming; for now point the binding at `bin/rishot` (or set `RISHOT_CONFIG_DIR`, see below).

## Features

- Region and monitor selection
- Window highlight on hover (Hyprland)
- Annotation tools: rectangle, ellipse, line, arrow, pen, marker, text, blur
- Undo and redo
- Copy to clipboard, save to disk, upload

## Upload

Upload posts to `litterbox.catbox.moe` by default. The returned link is unguessable but **public** and expires after 72 hours; it is not authenticated or private. Point `RISHOT_UPLOAD` at your own endpoint to use a different host. For anything sensitive, use copy or save instead of upload.

## Environment variables

- `RISHOT_CONFIG_DIR` — override the Quickshell config dir (the one holding `shell.qml`)
- `RISHOT_SAVEDIR` — override the auto-save directory
- `RISHOT_UPLOAD` — override the upload endpoint (curl form-post target)
- `RISHOT_KEYBIND_FILE` — path to a keybind file rishot may write when you rebind from the settings panel
