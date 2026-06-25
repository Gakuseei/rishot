import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Singletons"
import "lib/coords.js" as Coords
import "lib/AnnotationModel.js" as Ann
import "lib/hittest.js" as Hit

ShellRoot {
    id: root

    property var globalSel: null
    property var pressPoint: null
    property bool capturing: false
    property string phase: "selecting"
    property string activeTool: "rect"
    property color activeColor: Theme.vermilion
    property int activeWidth: 4
    property bool activeFill: false
    property var toolStyle: ({})

    property var model: Ann.create()
    property var draft: null
    property int annRevision: 0
    property int commitRevision: 0
    property bool settingsOpen: false
    property bool textEditing: false

    property real toolbarDX: 0
    property real toolbarDY: 0
    property string openPopover: ""

    /**
     * Canonical tool descriptors: id, icon, label and single-key shortcut. The
     * toolbar renders this list and the key handler derives toolKeys from it, so
     * the tooltips and Keys.onPressed shortcuts cannot drift apart.
     */
    readonly property var toolDescriptors: [
        { id: "select",   icon: "select",   label: "Select",    key: "v" },
        { id: "rect",     icon: "rect",     label: "Rectangle", key: "r" },
        { id: "ellipse",  icon: "ellipse",  label: "Ellipse",   key: "o" },
        { id: "line",     icon: "line",     label: "Line",      key: "l" },
        { id: "arrow",    icon: "arrow",    label: "Arrow",     key: "a" },
        { id: "pen",      icon: "pen",      label: "Pen",       key: "p" },
        { id: "marker",   icon: "marker",   label: "Marker",    key: "h" },
        { id: "step",     icon: "step",     label: "Step",      key: "n" },
        { id: "text",     icon: "text",     label: "Text",      key: "t" },
        { id: "blur",     icon: "blur",     label: "Blur",      key: "b" },
        { id: "pixelate", icon: "pixelate", label: "Pixelate",  key: "x" },
        { id: "zoom",     icon: "zoom",     label: "Zoom",      key: "z" }
    ]
    readonly property var toolKeys: {
        var m = {};
        for (var i = 0; i < toolDescriptors.length; i++)
            m[toolDescriptors[i].key] = toolDescriptors[i].id;
        return m;
    }

    function selectTool(t) {
        if (textEditing) commitText();
        clearSelection();
        activeTool = t;
        var s = toolStyle[t];
        activeColor = s ? s.color : Theme.vermilion;
        activeWidth = s ? s.width : 4;
        activeFill = s ? (s.filled === true) : false;
    }

    /** True for the closed shapes whose fill toggle is meaningful. */
    function toolHasFill(t) { return t === "rect" || t === "ellipse"; }

    function styleEntry() {
        return { color: String(activeColor), width: activeWidth, filled: activeFill };
    }

    function setToolColor(c) {
        activeColor = c;
        var s = Object.assign({}, toolStyle);
        s[activeTool] = styleEntry();
        toolStyle = s;
        persistToolStyle();
    }

    function setToolWidth(w) {
        activeWidth = w;
        var s = Object.assign({}, toolStyle);
        s[activeTool] = styleEntry();
        toolStyle = s;
        persistToolStyle();
    }

    function setToolFill(f) {
        activeFill = f;
        var s = Object.assign({}, toolStyle);
        s[activeTool] = styleEntry();
        toolStyle = s;
        persistToolStyle();
    }

    /**
     * Nudges the active tool's width by one scroll notch, clamped to 1..20, and
     * pushes the new width onto an open draft so the stroke or text resizes live.
     */
    function adjustWidth(dir) {
        var w = Math.max(1, Math.min(20, activeWidth + dir));
        if (w === activeWidth) return;
        setToolWidth(w);
        if (draft) {
            if (draft.type === "text") { draft = Object.assign({}, draft, { size: textSize() }); bumpAnn(); }
            else if (draft.width !== undefined) { draft.width = w; bumpAnn(); }
        }
    }

    /** Coalesces rapid style changes (a scroll burst) into one settings write. */
    Timer {
        id: persistTimer
        interval: 400
        onTriggered: { Config.toolStyle = root.toolStyle; Config.save(); }
    }
    function persistToolStyle() { persistTimer.restart(); }

    Connections {
        target: Config
        function onLoaded() {
            if (Config.toolStyle && typeof Config.toolStyle === "object")
                root.toolStyle = Config.toolStyle;
            root.selectTool(root.activeTool);
        }
    }

    property var selectedIndex: null
    property var moveOffset: null
    property var moveStart: null
    property var resizing: null
    property var hoverWindow: null
    property var windowRects: []
    property bool dialogMode: false
    property string savedAuto: ""

    function textSize() { return activeWidth * 5 + 8; }

    property var overlays: []
    property int captureFails: 0

    readonly property string mode: Quickshell.env("RISHOT_MODE") === "monitor" ? "monitor" : "region"
    readonly property string homeDir: Quickshell.env("HOME") || "/tmp"
    readonly property string tmpDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string shotsDir: Quickshell.env("RISHOT_SAVEDIR")
        || (Quickshell.env("XDG_PICTURES_DIR")
            ? Quickshell.env("XDG_PICTURES_DIR") + "/Screenshots"
            : homeDir + "/Pictures/Screenshots")
    readonly property string uploadEndpoint: Quickshell.env("RISHOT_UPLOAD")
        || "https://litterbox.catbox.moe/resources/internals/api.php"
    readonly property string keybindFile: Quickshell.env("RISHOT_KEYBIND_FILE") || ""

    /**
     * KWin implements none of the screencopy protocols ScreencopyView needs, so
     * on KDE the capture path switches to spectacle (see spectacleProc). RISHOT_CAPTURE
     * forces a backend; otherwise KDE picks spectacle and everything else uses
     * ScreencopyView. captureScale is spectacle's stitched-PNG scale, ceil of the
     * largest output ratio, used to crop each output out of the full-desktop shot.
     */
    readonly property string captureBackend: {
        var ov = Quickshell.env("RISHOT_CAPTURE");
        if (ov === "spectacle" || ov === "screencopy") return ov;
        var de = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase();
        return de.indexOf("kde") >= 0 ? "spectacle" : "screencopy";
    }
    readonly property real captureScale: {
        var s = Quickshell.screens, m = 1;
        for (var i = 0; i < s.length; i++) m = Math.max(m, s[i].devicePixelRatio || 1);
        return Math.ceil(m);
    }
    readonly property string frozenPng: tmpDir + "/rishot-frozen.png"
    property string frozenSource: ""

    /** Absolute path to the bundled torii icon, passed to notify-send -i. */
    readonly property string iconPath: {
        var u = Qt.resolvedUrl("rishot.svg").toString();
        return u.indexOf("file://") === 0 ? u.substring(7) : u;
    }

    function beginSelection(gx, gy) {
        pressPoint = { x: gx, y: gy };
        capturing = true;
        globalSel = { x: gx, y: gy, w: 0, h: 0 };
    }
    function updateSelection(gx, gy) {
        if (!pressPoint) return;
        globalSel = Coords.rectFromPoints(pressPoint, { x: gx, y: gy });
    }
    function endSelection() {
        capturing = false;
        pressPoint = null;
        if (globalSel && globalSel.w > 2 && globalSel.h > 2) { phase = "editing"; hoverWindow = null; }
        else if (hoverWindow) {
            globalSel = { x: hoverWindow.x, y: hoverWindow.y, w: hoverWindow.w, h: hoverWindow.h };
            phase = "editing";
            hoverWindow = null;
        } else globalSel = null;
    }

    /**
     * Starts a region-resize gesture. The role names which edge or corner is
     * being dragged ("l", "r", "t", "b", "tl", "tr", "bl", "br"); the opposite
     * side stays anchored for the duration.
     */
    function beginResize(role, gx, gy) { resizing = role; }

    /**
     * Recomputes globalSel by moving only the dragged edge(s) to the pointer,
     * clamping each axis to a minimum extent of 8px so the rect never collapses
     * or inverts. The anchored side is preserved.
     */
    function updateResize(gx, gy) {
        if (resizing === null || !globalSel) return;
        var s = globalSel, m = 8;
        var x0 = s.x, y0 = s.y, x1 = s.x + s.w, y1 = s.y + s.h;
        var r = resizing;
        if (r === "l" || r === "tl" || r === "bl") x0 = Math.min(gx, x1 - m);
        if (r === "r" || r === "tr" || r === "br") x1 = Math.max(gx, x0 + m);
        if (r === "t" || r === "tl" || r === "tr") y0 = Math.min(gy, y1 - m);
        if (r === "b" || r === "bl" || r === "br") y1 = Math.max(gy, y0 + m);
        globalSel = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }

    /** Ends the active region-resize gesture. */
    function endResize() { resizing = null; }

    function clampToSel(gx, gy) {
        var x = Math.max(globalSel.x, Math.min(gx, globalSel.x + globalSel.w));
        var y = Math.max(globalSel.y, Math.min(gy, globalSel.y + globalSel.h));
        return { x: x, y: y };
    }
    function isFreehand(t) { return t === "pen"; }

    function placeText(gx, gy) {
        if (textEditing) { commitText(); return; }
        var p = clampToSel(gx, gy);
        draft = { type: "text", points: [p], color: String(activeColor), text: "", size: textSize() };
        textEditing = true;
        bumpAnn();
    }
    function commitText() {
        if (draft && draft.type === "text") {
            if (draft.text && draft.text.length > 0) model.add(draft);
        }
        draft = null;
        textEditing = false;
        bumpCommit();
    }
    function cancelText() {
        draft = null;
        textEditing = false;
        bumpAnn();
    }

    /**
     * Places a numbered step badge at the clamped point. The label is the
     * highest existing step number plus one, so deleting a middle badge leaves
     * a gap (flameshot-style) instead of producing duplicate labels.
     */
    function placeStep(gx, gy) {
        var p = clampToSel(gx, gy);
        var n = 0;
        for (var i = 0; i < model.items.length; i++)
            if (model.items[i].type === "step" && model.items[i].n > n) n = model.items[i].n;
        model.add({
            type: "step",
            points: [p],
            color: String(activeColor),
            n: n + 1,
            size: activeWidth * 4 + 16
        });
        bumpCommit();
    }

    function clearSelection() {
        if (selectedIndex !== null) { selectedIndex = null; bumpAnn(); }
    }

    function deleteSelected() {
        if (selectedIndex === null) return;
        model.remove(selectedIndex);
        selectedIndex = null;
        bumpCommit();
    }

    function beginSelect(gx, gy) {
        var idx = Hit.hitTest(model.items, gx, gy);
        selectedIndex = idx;
        if (idx !== null) {
            capturing = true;
            moveStart = { x: gx, y: gy };
            moveOffset = { x: 0, y: 0 };
        }
        bumpAnn();
    }
    function updateSelect(gx, gy) {
        if (selectedIndex === null || !moveStart) return;
        moveOffset = { x: gx - moveStart.x, y: gy - moveStart.y };
        bumpAnn();
    }
    function endSelect() {
        capturing = false;
        if (selectedIndex !== null && moveOffset
            && (moveOffset.x !== 0 || moveOffset.y !== 0)) {
            model.move(selectedIndex, moveOffset.x, moveOffset.y);
        }
        moveOffset = null;
        moveStart = null;
        bumpCommit();
    }

    function beginDraw(gx, gy) {
        if (!globalSel || activeTool === "select") return;
        if (activeTool === "text") { placeText(gx, gy); return; }
        if (activeTool === "step") { placeStep(gx, gy); return; }
        var p = clampToSel(gx, gy);
        pressPoint = p;
        capturing = true;
        if (isFreehand(activeTool))
            draft = { type: activeTool, points: [p], color: String(activeColor), width: activeWidth };
        else if (activeTool === "marker")
            draft = { type: "marker", points: [p, p], color: String(Theme.markerYellow), width: activeWidth, filled: true };
        else if (activeTool === "blur" || activeTool === "pixelate")
            draft = { type: activeTool, points: [p, p] };
        else if (activeTool === "zoom")
            draft = { type: "zoom", points: [p, p], zoom: Config.zoomFactor };
        else
            draft = { type: activeTool, points: [p, p], color: String(activeColor), width: activeWidth, filled: activeFill };
        bumpAnn();
    }
    function updateDraw(gx, gy) {
        if (!draft || !pressPoint || draft.type === "text") return;
        var p = clampToSel(gx, gy);
        if (isFreehand(draft.type)) {
            var last = draft.points[draft.points.length - 1];
            if (Math.abs(p.x - last.x) < 2 && Math.abs(p.y - last.y) < 2) return;
            draft.points.push(p);
        } else {
            draft.points = [pressPoint, p];
        }
        bumpAnn();
    }
    function endDraw() {
        capturing = false;
        if (!draft || draft.type === "text") return;
        if (isFreehand(draft.type)) {
            if (draft.points.length >= 2) model.add(draft);
        } else {
            var p0 = draft.points[0], p1 = draft.points[1];
            var dx = Math.abs(p1.x - p0.x), dy = Math.abs(p1.y - p0.y);
            var big = draft.type === "line" || draft.type === "arrow"
                ? Math.hypot(dx, dy) > 4
                : dx > 2 && dy > 2;
            if (big) model.add(draft);
        }
        draft = null;
        pressPoint = null;
        bumpCommit();
    }
    /**
     * annRevision ticks on every change including live draft points, so the draft
     * and selection layers re-render at pointer speed. commitRevision ticks only
     * when model.items actually changes (add/remove/move/undo/redo), so the heavy
     * committed-annotation Repeaters rebuild on discrete edits, not per draft point.
     */
    function bumpAnn() { annRevision += 1; }
    function bumpCommit() { commitRevision += 1; annRevision += 1; }

    function undo() { if (model.undo()) { selectedIndex = null; moveOffset = null; moveStart = null; bumpCommit(); } }
    function redo() { if (model.redo()) { selectedIndex = null; moveOffset = null; moveStart = null; bumpCommit(); } }

    function windowAt(gx, gy) {
        var best = null;
        for (var i = 0; i < windowRects.length; i++) {
            var r = windowRects[i];
            if (gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h) {
                if (best === null || r.z < best.z) best = r;
            }
        }
        return best ? { x: best.x, y: best.y, w: best.w, h: best.h } : null;
    }
    function monitorAt(gx, gy) {
        var scr = Quickshell.screens;
        for (var i = 0; i < scr.length; i++) {
            var s = scr[i];
            if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height)
                return { x: s.x, y: s.y, w: s.width, h: s.height };
        }
        return null;
    }
    function selectMonitor(gx, gy) {
        var m = monitorAt(gx, gy);
        if (!m) return;
        globalSel = m;
        phase = "editing";
        hoverWindow = null;
    }
    function pointerHover(gx, gy) {
        if (phase !== "selecting") { if (hoverWindow !== null) hoverWindow = null; return; }
        hoverWindow = mode === "monitor" ? monitorAt(gx, gy) : windowAt(gx, gy);
    }
    function pointerPressed(gx, gy) {
        if (resizing !== null) return;
        if (phase === "selecting") {
            if (mode === "monitor") selectMonitor(gx, gy);
            else beginSelection(gx, gy);
        }
        else if (activeTool === "select") beginSelect(gx, gy);
        else beginDraw(gx, gy);
    }
    function pointerMoved(gx, gy) {
        if (resizing !== null) return;
        if (phase === "selecting") updateSelection(gx, gy);
        else if (activeTool === "select") updateSelect(gx, gy);
        else updateDraw(gx, gy);
    }
    function pointerReleased() {
        if (phase === "selecting") endSelection();
        else if (activeTool === "select") endSelect();
        else endDraw();
    }

    function timestampName() {
        var d = new Date();
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return "shot-" + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate())
            + "-" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()) + ".png";
    }
    /** Save target: the folder picked in settings, or shotsDir when none is set. */
    readonly property string effectiveSaveDir: Config.saveDir !== "" ? Config.saveDir : shotsDir
    readonly property string defaultPath: effectiveSaveDir + "/" + timestampName()

    function anchorOverlay() {
        if (!globalSel) return null;
        for (var i = 0; i < overlays.length; i++) {
            var w = overlays[i];
            var s = w.modelData;
            if (globalSel.x >= s.x && globalSel.x < s.x + s.width
                && globalSel.y >= s.y && globalSel.y < s.y + s.height) return w;
        }
        return overlays.length ? overlays[0] : null;
    }

    function spansMonitors() {
        if (!globalSel) return false;
        var hit = 0;
        for (var i = 0; i < overlays.length; i++) {
            var s = overlays[i].modelData;
            if (Coords.intersectRect(globalSel, { x: s.x, y: s.y, width: s.width, height: s.height })) hit++;
        }
        return hit > 1;
    }

    function grabTo(path, after) {
        var w = anchorOverlay();
        if (!w) { if (after) after(false); return; }
        if (spansMonitors()) { seamStitch(path, after); return; }
        w.grabExport(path, function (ok) {
            console.log("rishot: grab " + path + " => " + ok);
            if (after) after(ok);
        });
    }

    function seamStitch(path, after) {
        var slices = [];
        for (var i = 0; i < overlays.length; i++) {
            var s = overlays[i].modelData;
            var inter = Coords.intersectRect(globalSel, { x: s.x, y: s.y, width: s.width, height: s.height });
            if (!inter) continue;
            slices.push({
                win: overlays[i],
                tmp: root.tmpDir + "/rishot-seam-" + i + ".png",
                ox: Math.round(s.x + inter.x - globalSel.x),
                oy: Math.round(s.y + inter.y - globalSel.y)
            });
        }
        if (slices.length === 0) { if (after) after(false); return; }
        if (slices.length === 1) { slices[0].win.grabExport(path, after); return; }
        var done = 0, okAll = true;
        for (var j = 0; j < slices.length; j++) {
            (function (sl) {
                sl.win.grabExport(sl.tmp, function (ok) {
                    if (!ok) okAll = false;
                    done += 1;
                    if (done === slices.length) compositeSlices(slices, path, okAll, after);
                });
            })(slices[j]);
        }
    }

    function compositeSlices(slices, path, okAll, after) {
        if (!okAll) { console.log("rishot: seam-stitch slice grab failed"); if (after) after(false); return; }
        var args = ["magick", "-size", Math.round(globalSel.w) + "x" + Math.round(globalSel.h), "xc:black"];
        for (var i = 0; i < slices.length; i++)
            args = args.concat([slices[i].tmp, "-geometry", "+" + slices[i].ox + "+" + slices[i].oy, "-composite"]);
        args.push(path);
        stitchProc.runWith(args, after);
    }

    /** Maps an absolute path under $HOME to a ~-prefixed display string. */
    function pretty(p) {
        return (root.homeDir.length > 0 && p.indexOf(root.homeDir) === 0)
            ? "~" + p.slice(root.homeDir.length) : p;
    }

    /**
     * Fires a desktop notification and closes right away. Copy and save route
     * through here so they leave a trace without holding the overlay (and its
     * exclusive keyboard grab) open. When openPath is set the toast carries an
     * Open action; the worker is detached so qs quits at once while the
     * notification outlives it to catch the click and xdg-open the file (the
     * action signal would reach a dead app otherwise). notify-send is optional;
     * the sh wrapper still exits 0 when it is missing.
     */
    function finish(summary, body, isError, openPath) {
        dialogMode = false;
        notifyProc.send(summary, body || "", isError === true, openPath || "");
    }

    Process {
        id: notifyProc
        function send(summary, body, isError, openPath) {
            command = ["setsid", "-f", "sh", "-c",
                "exec 9>&-; command -v notify-send >/dev/null 2>&1 || exit 0; "
                + "if [ -n \"$5\" ]; then "
                + "act=$(notify-send -a rishot -i \"$1\" -u \"$2\" -A \"open=Open\" \"$3\" \"$4\"); "
                + "[ \"$act\" = open ] && xdg-open \"$5\"; "
                + "else notify-send -a rishot -i \"$1\" -u \"$2\" \"$3\" \"$4\"; fi",
                "_", root.iconPath, isError ? "critical" : "normal", summary, body, openPath];
            running = true;
        }
        onExited: () => Qt.quit()
    }

    /**
     * Copy honours the "save a copy on disk" setting. When off the shot lands in
     * a throwaway tmp file that copyProc deletes after it reaches the clipboard,
     * so a plain copy leaves no screenshot behind. When on it writes to the
     * normal shots dir and keeps it, same as save.
     */
    function doCopy() {
        var keep = Config.copyToDisk;
        var target = keep ? defaultPath : (root.tmpDir + "/rishot-copy.png");
        grabTo(target, function (ok) {
            if (ok) copyProc.run(target, keep);
            else root.finish("Capture failed", "", true, "");
        });
    }

    function doSave() {
        var auto = root.defaultPath;
        grabTo(auto, function (ok) {
            if (!ok) { root.finish("Capture failed", "", true, ""); return; }
            root.savedAuto = auto;
            if (Config.skipSaveDialog) { root.afterSave(auto); return; }
            root.dialogMode = true;
            saveDialog.open();
        });
    }

    /**
     * Finishes a save: the file is already on disk at path, so this only adds the
     * clipboard copy when the copy-on-save setting is on, then fires the toast.
     */
    function afterSave(path) {
        if (Config.copyOnSave) saveCopyProc.run(path);
        else root.finish("Screenshot saved", root.pretty(path), false, path);
    }

    function doUpload() {
        var tmp = root.tmpDir + "/rishot-upload.png";
        grabTo(tmp, function (ok) {
            if (ok) uploadProc.run(tmp);
            else root.finish("Capture failed", "", true, "");
        });
    }

    Process {
        id: saveDialog
        stdout: StdioCollector { id: saveOut }
        function open() {
            command = ["kdialog", "--getsavefilename", root.savedAuto, "*.png"];
            running = true;
        }
        onExited: (code) => {
            var chosen = saveOut.text.trim();
            console.log("rishot: kdialog exit " + code + " path=" + JSON.stringify(chosen));
            if (code === 0 && chosen.length > 0) {
                if (chosen !== root.savedAuto) copyFileProc.run(root.savedAuto, chosen);
                else root.afterSave(root.savedAuto);
            } else {
                root.dialogMode = false;
            }
        }
    }

    Process {
        id: copyFileProc
        property string dst: ""
        function run(src, d) { dst = d; command = ["cp", "--", src, d]; running = true; }
        onExited: () => root.afterSave(dst)
    }

    /** Puts an already-saved file on the clipboard for the copy-on-save option. */
    Process {
        id: saveCopyProc
        property string p: ""
        function run(path) {
            p = path;
            command = ["sh", "-c", "exec 9>&-; wl-copy --type image/png < \"$1\"", "_", path];
            running = true;
        }
        onExited: () => root.finish("Screenshot saved", root.pretty(p), false, p)
    }

    /**
     * Folder picker for the save directory. The overlay holds an exclusive
     * keyboard grab, so dialogMode drops it while kdialog runs and the overlay
     * returns with its frozen capture intact once a folder is chosen or the
     * picker is cancelled.
     */
    Process {
        id: saveDirPick
        stdout: StdioCollector { id: saveDirOut }
        function open() {
            root.dialogMode = true;
            command = ["kdialog", "--getexistingdirectory", root.effectiveSaveDir];
            running = true;
        }
        onExited: (code) => {
            root.dialogMode = false;
            var dir = saveDirOut.text.trim();
            if (code === 0 && dir.length > 0) { Config.saveDir = dir; Config.save(); }
        }
    }

    Process {
        id: copyProc
        property string file: ""
        property bool keep: true
        function run(f, keepFile) {
            file = f;
            keep = keepFile;
            command = ["sh", "-c",
                "exec 9>&-; wl-copy --type image/png < \"$1\"; "
                + "if command -v cliphist >/dev/null 2>&1; then "
                + "if [ \"$(stat -c%s \"$1\")\" -ge 4900000 ]; then "
                + "command -v magick >/dev/null 2>&1 && magick \"$1\" -quality 92 jpeg:- | cliphist store; "
                + "else cliphist store < \"$1\"; fi; fi; "
                + "[ \"$2\" = keep ] || rm -f \"$1\"",
                "_", f, keep ? "keep" : "drop"];
            running = true;
        }
        onExited: (code) => {
            console.log("rishot: wl-copy exit " + code);
            if (code !== 0) { root.finish("Copy failed", "", true, ""); return; }
            if (keep) root.finish("Screenshot copied", root.pretty(file), false, file);
            else root.finish("Copied to clipboard", "", false, "");
        }
    }

    /**
     * Uploads detached so the overlay closes instantly. setsid -f forks the
     * worker into its own session and its parent returns at once (onExited quits
     * qs); the worker strips metadata, posts, copies the link and fires the
     * result notification on its own. exec 9>&- drops the single-instance lock fd
     * so a fresh launch is not blocked while the upload runs.
     */
    Process {
        id: uploadProc
        function run(file) {
            command = ["setsid", "-f", "sh", "-c",
                "exec 9>&-; "
                + "command -v magick >/dev/null 2>&1 && magick \"$1\" -strip \"$1\" >/dev/null 2>&1; "
                + "url=$(curl -sf --proto '=https' --max-time 30 -A \"Mozilla/5.0\" "
                + "-F reqtype=fileupload -F time=72h -F fileToUpload=@\"$1\" \"$2\"); "
                + "rm -f \"$1\"; "
                + "if [ -n \"$url\" ] && [ \"${url#http}\" != \"$url\" ]; then "
                + "printf %s \"$url\" | wl-copy; "
                + "command -v notify-send >/dev/null 2>&1 || exit 0; "
                + "act=$(notify-send -a rishot -i \"$3\" -u normal -A \"copy=Copy link\" 'Link copied' \"$url\"); "
                + "[ \"$act\" = copy ] && printf %s \"$url\" | wl-copy; "
                + "else command -v notify-send >/dev/null 2>&1 && "
                + "notify-send -a rishot -i \"$3\" -u critical rishot 'Upload failed'; fi",
                "_", file, root.uploadEndpoint, root.iconPath];
            running = true;
        }
        onExited: () => Qt.quit()
    }

    WindowProvider {
        id: windowProvider
        onWindowsReady: (rects) => root.windowRects = rects
    }

    /**
     * KDE capture. KWin lets no unprivileged client speak a screencopy protocol,
     * but spectacle is allowlisted for its screenshot interface, so we grab the
     * whole desktop through it once and each overlay shows its slice. Background
     * plus no-notify keep it silent and the default leaves the cursor out. The
     * overlays stay unmapped until frozenSource is set so the shot never catches
     * rishot's own surface. exit 127 means spectacle is not installed.
     */
    Process {
        id: spectacleProc
        command: ["sh", "-c",
            "command -v spectacle >/dev/null 2>&1 || exit 127; exec spectacle -bnf -o \"$1\"",
            "_", root.frozenPng]
        onExited: (code) => {
            if (code === 0) { root.frozenSource = "file://" + root.frozenPng; return; }
            if (code === 127)
                root.finish("rishot needs spectacle on KDE",
                    "KWin has no screencopy protocol; install spectacle to capture", true, "");
            else
                root.finish("Capture failed", "spectacle exited " + code, true, "");
        }
    }

    Component.onCompleted: {
        windowProvider.refresh();
        if (root.captureBackend === "spectacle") spectacleProc.running = true;
    }

    Process {
        id: stitchProc
        property var cb: null
        function runWith(args, after) { cb = after; command = args; running = true; }
        onExited: (code) => {
            console.log("rishot: seam-stitch composite exit " + code);
            seamCleanup.command = ["sh", "-c", "rm -f \"$1\"/rishot-seam-*.png", "_", root.tmpDir];
            seamCleanup.running = true;
            var f = cb;
            cb = null;
            if (f) f(code === 0);
        }
    }

    Process { id: seamCleanup }

    Process {
        id: mkdirProc
        running: true
        command: ["mkdir", "-p", root.shotsDir]
    }

    function toolbarFor(win) {
        if (phase !== "editing" || !globalSel) return { visible: false, x: 0, y: 0 };
        if (anchorOverlay() !== win) return { visible: false, x: 0, y: 0 };
        return { visible: true };
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: !root.dialogMode
                && (root.captureBackend !== "spectacle" || root.frozenSource !== "")

            anchors { top: true; left: true; right: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "rishot"

            readonly property string scrName: win.modelData.name
            readonly property bool showToolbar: root.toolbarFor(win).visible

            readonly property var selLocal: root.globalSel
                ? Coords.intersectRect(root.globalSel,
                    { x: win.modelData.x, y: win.modelData.y, width: win.width, height: win.height })
                : null

            FocusScope {
                id: keyScope
                anchors.fill: parent
                focus: true

                /**
                 * Re-asserts scope focus once no overlay child holds it. The
                 * SettingsPanel key-catcher and the colour hex field grab active
                 * focus while open; when they hide, Qt drops their focus without
                 * restoring the scope default, which would silently kill the
                 * single-key tool shortcuts. Re-grabbing here keeps them live.
                 */
                function reclaimFocus() {
                    if (!root.textEditing && root.openPopover === "" && !root.settingsOpen)
                        keyScope.forceActiveFocus();
                }

                Connections {
                    target: root
                    function onOpenPopoverChanged() { keyScope.reclaimFocus(); }
                    function onSettingsOpenChanged() { keyScope.reclaimFocus(); }
                }

                Keys.onEscapePressed: {
                    if (root.textEditing) root.cancelText();
                    else if (root.openPopover !== "") root.openPopover = "";
                    else if (root.settingsOpen) root.settingsOpen = false;
                    else if (root.selectedIndex !== null) root.clearSelection();
                    else Qt.quit();
                }
                Keys.onPressed: (e) => {
                    if (root.textEditing) return;
                    if (e.modifiers & Qt.ControlModifier) {
                        if (e.key === Qt.Key_C) { root.doCopy(); e.accepted = true; }
                        else if (e.key === Qt.Key_S) { if (root.phase === "editing") root.doSave(); e.accepted = true; }
                        else if (e.key === Qt.Key_U) { if (root.phase === "editing") root.doUpload(); e.accepted = true; }
                        else if (e.key === Qt.Key_Z) { root.undo(); e.accepted = true; }
                        else if (e.key === Qt.Key_Y) { root.redo(); e.accepted = true; }
                        return;
                    }
                    if (e.modifiers & (Qt.AltModifier | Qt.MetaModifier)) return;
                    if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && root.selectedIndex !== null) {
                        root.deleteSelected();
                        e.accepted = true;
                        return;
                    }
                    var t = root.toolKeys[e.text];
                    if (t !== undefined) {
                        root.openPopover = "";
                        root.selectTool(t);
                        e.accepted = true;
                    } else if (root.phase === "editing" && e.text === ",") {
                        root.openPopover = "";
                        root.settingsOpen = !root.settingsOpen;
                        e.accepted = true;
                    } else if (root.phase === "editing" && e.text === "c") {
                        root.settingsOpen = false;
                        root.openPopover = root.openPopover === "color" ? "" : "color";
                        e.accepted = true;
                    } else if (root.phase === "editing" && e.text === "w") {
                        root.settingsOpen = false;
                        root.openPopover = root.openPopover === "width" ? "" : "width";
                        e.accepted = true;
                    } else if (root.phase === "editing" && e.text === "f" && root.toolHasFill(root.activeTool)) {
                        root.setToolFill(!root.activeFill);
                        e.accepted = true;
                    }
                }

                Overlay {
                    id: ov
                    anchors.fill: parent
                    screenData: win.modelData
                    captureBackend: root.captureBackend
                    captureScale: root.captureScale
                    frozenSource: root.frozenSource
                    globalSel: root.globalSel
                    capturing: root.capturing
                    phase: root.phase
                    model: root.model
                    draft: root.draft
                    annRevision: root.annRevision
                    commitRevision: root.commitRevision
                    textEditing: root.textEditing
                    selectedIndex: root.selectedIndex
                    moveOffset: root.moveOffset
                    hoverWindow: root.hoverWindow

                    onPressedAt: (gx, gy) => root.pointerPressed(gx, gy)
                    onMovedTo: (gx, gy) => root.pointerMoved(gx, gy)
                    onHovered: (gx, gy) => root.pointerHover(gx, gy)
                    onReleased: root.pointerReleased()
                    onWheelStep: (dir) => root.adjustWidth(dir)
                    onResizeStarted: (role, gx, gy) => root.beginResize(role, gx, gy)
                    onResizeMoved: (gx, gy) => root.updateResize(gx, gy)
                    onResizeEnded: root.endResize()
                    onCaptureTimedOut: {
                        root.captureFails += 1;
                        if (root.captureFails >= Quickshell.screens.length) {
                            console.warn("rishot: no screen produced a frame, quitting");
                            Qt.quit();
                        }
                    }
                    onTextChanged: (t) => { if (root.draft && root.draft.type === "text") { root.draft.text = t; root.bumpAnn(); } }
                    onTextCommitted: root.commitText()
                }

                Toolbar {
                    id: toolbar
                    visible: win.showToolbar && win.selLocal !== null
                    tools: root.toolDescriptors
                    activeTool: root.activeTool
                    activeColor: root.activeColor
                    activeWidth: root.activeWidth
                    activeFill: root.activeFill
                    canUndo: { root.commitRevision; return root.model ? root.model.canUndo() : false; }
                    canRedo: { root.commitRevision; return root.model ? root.model.canRedo() : false; }
                    settingsOpen: root.settingsOpen

                    x: {
                        if (!win.selLocal) return 0;
                        var cx = win.selLocal.x + win.selLocal.w / 2 - width / 2 + root.toolbarDX;
                        return Math.max(8, Math.min(cx, win.width - width - 8));
                    }
                    y: {
                        if (!win.selLocal) return 0;
                        var below = win.selLocal.y + win.selLocal.h + 12;
                        if (below + height > win.height - 8) below = win.selLocal.y - height - 12;
                        return Math.max(8, Math.min(below + root.toolbarDY, win.height - height - 8));
                    }

                    onToolPicked: (t) => root.selectTool(t)
                    onColorButtonClicked: { root.settingsOpen = false; root.openPopover = root.openPopover === "color" ? "" : "color"; }
                    onWidthButtonClicked: { root.settingsOpen = false; root.openPopover = root.openPopover === "width" ? "" : "width"; }
                    onFillToggled: root.setToolFill(!root.activeFill)
                    onUndoRequested: root.undo()
                    onRedoRequested: root.redo()
                    onCopyRequested: root.doCopy()
                    onSaveRequested: root.doSave()
                    onUploadRequested: root.doUpload()
                    onSettingsRequested: { root.openPopover = ""; root.settingsOpen = !root.settingsOpen; }
                    onDragMoved: (dx, dy) => {
                        if (!win.selLocal) return;
                        var ax = win.selLocal.x + win.selLocal.w / 2 - toolbar.width / 2;
                        var ay = win.selLocal.y + win.selLocal.h + 12;
                        if (ay + toolbar.height > win.height - 8) ay = win.selLocal.y - toolbar.height - 12;
                        var minDX = 8 - ax, maxDX = (win.width - toolbar.width - 8) - ax;
                        var minDY = 8 - ay, maxDY = (win.height - toolbar.height - 8) - ay;
                        root.toolbarDX = Math.max(minDX, Math.min(root.toolbarDX + dx, maxDX));
                        root.toolbarDY = Math.max(minDY, Math.min(root.toolbarDY + dy, maxDY));
                    }
                    onDragReset: { root.toolbarDX = 0; root.toolbarDY = 0; }
                }

                SettingsPanel {
                    id: hotkeyPopover
                    visible: toolbar.visible && root.settingsOpen
                    luaPath: root.keybindFile
                    x: Math.max(8, Math.min(toolbar.x + toolbar.gearCenterX - width / 2,
                                            win.width - width - 8))
                    y: {
                        var above = toolbar.y - height - 6;
                        if (above < 8) {
                            var below = toolbar.y + toolbar.height + 6;
                            return Math.min(below, win.height - height - 8);
                        }
                        return above;
                    }
                    onCloseRequested: root.settingsOpen = false
                    onRebound: Qt.quit()
                    onPickSaveDir: saveDirPick.open()
                }

                ColorPopover {
                    id: colorPopover
                    visible: toolbar.visible && root.openPopover === "color"
                    selected: root.activeColor
                    x: Math.max(8, Math.min(toolbar.x + toolbar.colorCenterX - width / 2,
                                            win.width - width - 8))
                    y: Math.min(toolbar.y + toolbar.height + 6, win.height - height - 8)
                    onPicked: (c) => root.setToolColor(c)
                }

                WidthPopover {
                    id: widthPopover
                    visible: toolbar.visible && root.openPopover === "width"
                    selected: root.activeWidth
                    x: Math.max(8, Math.min(toolbar.x + toolbar.widthCenterX - width / 2,
                                            win.width - width - 8))
                    y: Math.min(toolbar.y + toolbar.height + 6, win.height - height - 8)
                    onPicked: (w) => { root.setToolWidth(w); root.openPopover = ""; }
                }

            }

            Component.onCompleted: root.overlays.push(win)

            function grabExport(path, cb) { ov.grabExport(path, cb); }
        }
    }
}
