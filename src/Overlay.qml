import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Wayland
import "Singletons"
import "lib/coords.js" as Coords

Item {
    id: overlay
    anchors.fill: parent

    required property var screenData
    property var globalSel: null
    property bool capturing: false
    property bool ready: false
    property string phase: ""

    property var model: null
    property var draft: null
    property int annRevision: 0
    property bool textEditing: false
    property var selectedIndex: null
    property var moveOffset: null
    property var hoverWindow: null

    signal pressedAt(real gx, real gy)
    signal movedTo(real gx, real gy)
    signal hovered(real gx, real gy)
    signal released()
    signal frozen()
    signal textChanged(string t)
    signal textCommitted()
    signal resizeStarted(string role, real gx, real gy)
    signal resizeMoved(real gx, real gy)
    signal resizeEnded()

    readonly property int sx: screenData.x
    readonly property int sy: screenData.y

    readonly property var localSel: globalSel
        ? Coords.intersectRect(globalSel, { x: sx, y: sy, width: width, height: height })
        : null

    readonly property color dimColor: Theme.dim
    readonly property color vermilion: Theme.vermilion

    function selectionBox() {
        if (selectedIndex === null || !model
            || selectedIndex < 0 || selectedIndex >= model.items.length) return null;
        var a = model.items[selectedIndex];
        var off = moveOffset || { x: 0, y: 0 };
        var xs = a.points.map(function (p) { return p.x; });
        var ys = a.points.map(function (p) { return p.y; });
        var x0 = Math.min.apply(null, xs), x1 = Math.max.apply(null, xs);
        var y0 = Math.min.apply(null, ys), y1 = Math.max.apply(null, ys);
        var pad = Math.max((a.width || 4), 6);
        if (a.type === "text") {
            var size = a.size || 16;
            x1 = x0 + Math.max((a.text ? a.text.length : 1) * size * 0.6, size);
            y1 = y0 + size * 1.4;
            pad = 4;
        }
        if (a.type === "step") {
            var d = a.size || 32;
            x0 -= d / 2; y0 -= d / 2;
            x1 = x0 + d; y1 = y0 + d;
            pad = 4;
        }
        return {
            x: x0 - sx + off.x - pad,
            y: y0 - sy + off.y - pad,
            w: (x1 - x0) + pad * 2,
            h: (y1 - y0) + pad * 2
        };
    }

    readonly property var selBox: { annRevision; return selectionBox(); }

    Item {
        id: scene
        anchors.fill: parent

        ScreencopyView {
            id: frozen
            anchors.fill: parent
            captureSource: overlay.screenData
            live: false
            paintCursor: false
        }

        readonly property real mosaicFactor: 14

        function blurItems() {
            var src = overlay.model ? overlay.model.items : [];
            var out = [];
            for (var i = 0; i < src.length; i++)
                if (src[i] && src[i].type === "blur") out.push(src[i]);
            if (overlay.draft && overlay.draft.type === "blur") out.push(overlay.draft);
            return out;
        }

        function pixelateItems() {
            var src = overlay.model ? overlay.model.items : [];
            var out = [];
            for (var i = 0; i < src.length; i++)
                if (src[i] && src[i].type === "pixelate") out.push(src[i]);
            if (overlay.draft && overlay.draft.type === "pixelate") out.push(overlay.draft);
            return out;
        }

        Repeater {
            model: { overlay.annRevision; return scene.blurItems(); }

            Item {
                required property var modelData
                readonly property var a: modelData
                readonly property bool valid: a !== undefined && a !== null && a.points !== undefined && a.points.length >= 2
                readonly property real rx: valid ? Math.min(a.points[0].x, a.points[1].x) - overlay.sx : 0
                readonly property real ry: valid ? Math.min(a.points[0].y, a.points[1].y) - overlay.sy : 0
                readonly property real rw: valid ? Math.abs(a.points[1].x - a.points[0].x) : 0
                readonly property real rh: valid ? Math.abs(a.points[1].y - a.points[0].y) : 0
                x: rx
                y: ry
                width: rw
                height: rh
                visible: valid && rw > 0 && rh > 0
                clip: true

                ShaderEffectSource {
                    id: blurSrc
                    sourceItem: frozen
                    anchors.fill: parent
                    live: false
                    recursive: false
                    sourceRect: Qt.rect(parent.rx, parent.ry, parent.rw, parent.rh)
                    visible: false
                }

                FastBlur {
                    anchors.fill: parent
                    source: blurSrc
                    radius: 64
                }
            }
        }

        Repeater {
            model: { overlay.annRevision; return scene.pixelateItems(); }

            Item {
                required property var modelData
                readonly property var a: modelData
                readonly property bool valid: a !== undefined && a !== null && a.points !== undefined && a.points.length >= 2
                readonly property real rx: valid ? Math.min(a.points[0].x, a.points[1].x) - overlay.sx : 0
                readonly property real ry: valid ? Math.min(a.points[0].y, a.points[1].y) - overlay.sy : 0
                readonly property real rw: valid ? Math.abs(a.points[1].x - a.points[0].x) : 0
                readonly property real rh: valid ? Math.abs(a.points[1].y - a.points[0].y) : 0
                x: rx
                y: ry
                width: rw
                height: rh
                visible: valid && rw > 0 && rh > 0
                clip: true

                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: frozen
                    live: false
                    recursive: false
                    smooth: false
                    sourceRect: Qt.rect(parent.rx, parent.ry, parent.rw, parent.rh)
                    textureSize: Qt.size(Math.max(1, parent.rw / scene.mosaicFactor),
                                         Math.max(1, parent.rh / scene.mosaicFactor))
                }
            }
        }

        AnnLayer {
            id: annCanvas
            anchors.fill: parent
            sx: overlay.sx
            sy: overlay.sy
            model: overlay.model
            draft: overlay.draft
            revision: overlay.annRevision
            selectedIndex: overlay.selectedIndex
            moveOffset: overlay.moveOffset
        }
    }

    Timer {
        id: capTimer
        interval: 50
        repeat: true
        running: true
        property int tries: 0
        onTriggered: {
            tries += 1;
            if (frozen.hasContent) {
                running = false;
                overlay.ready = true;
                overlay.frozen();
            } else if (tries > 60) {
                running = false;
            } else {
                frozen.captureFrame();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: overlay.dimColor
        visible: overlay.ready && overlay.localSel === null
    }

    Item {
        anchors.fill: parent
        visible: overlay.ready && overlay.localSel !== null
        Rectangle {
            color: overlay.dimColor
            x: 0; y: 0; width: parent.width
            height: overlay.localSel ? overlay.localSel.y : 0
        }
        Rectangle {
            color: overlay.dimColor
            x: 0; width: parent.width
            y: overlay.localSel ? overlay.localSel.y + overlay.localSel.h : 0
            height: overlay.localSel ? parent.height - (overlay.localSel.y + overlay.localSel.h) : 0
        }
        Rectangle {
            color: overlay.dimColor
            x: 0
            y: overlay.localSel ? overlay.localSel.y : 0
            width: overlay.localSel ? overlay.localSel.x : 0
            height: overlay.localSel ? overlay.localSel.h : 0
        }
        Rectangle {
            color: overlay.dimColor
            x: overlay.localSel ? overlay.localSel.x + overlay.localSel.w : 0
            y: overlay.localSel ? overlay.localSel.y : 0
            width: overlay.localSel ? parent.width - (overlay.localSel.x + overlay.localSel.w) : 0
            height: overlay.localSel ? overlay.localSel.h : 0
        }
    }

    Item {
        id: chrome
        visible: overlay.ready && overlay.localSel !== null
        x: overlay.localSel ? overlay.localSel.x : 0
        y: overlay.localSel ? overlay.localSel.y : 0
        width: overlay.localSel ? overlay.localSel.w : 0
        height: overlay.localSel ? overlay.localSel.h : 0

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: overlay.vermilion
            border.width: 1.5
        }

        Text {
            text: overlay.globalSel
                ? "⛩ rishot · " + Math.round(overlay.globalSel.w) + "×" + Math.round(overlay.globalSel.h)
                : ""
            color: overlay.vermilion
            font.family: Theme.monoFamily
            font.pixelSize: 13
            x: 0
            y: -height - 4
        }
    }

    Item {
        id: winHighlight
        readonly property var hw: overlay.hoverWindow
            ? Coords.intersectRect(overlay.hoverWindow, { x: overlay.sx, y: overlay.sy, width: overlay.width, height: overlay.height })
            : null
        visible: overlay.ready && overlay.globalSel === null && hw !== null
        x: hw ? hw.x : 0
        y: hw ? hw.y : 0
        width: hw ? hw.w : 0
        height: hw ? hw.h : 0

        Rectangle {
            anchors.fill: parent
            color: Theme.winFill
            border.color: overlay.vermilion
            border.width: 2.5
            antialiasing: true
        }
    }

    Item {
        id: annSelection
        visible: overlay.ready && overlay.selBox !== null
        x: overlay.selBox ? overlay.selBox.x : 0
        y: overlay.selBox ? overlay.selBox.y : 0
        width: overlay.selBox ? overlay.selBox.w : 0
        height: overlay.selBox ? overlay.selBox.h : 0

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: overlay.vermilion
            border.width: 1
            antialiasing: true
        }

        Repeater {
            model: [
                { hx: 0, hy: 0 },
                { hx: 1, hy: 0 },
                { hx: 0, hy: 1 },
                { hx: 1, hy: 1 }
            ]
            Rectangle {
                required property var modelData
                width: 7; height: 7
                radius: 1
                color: overlay.vermilion
                x: modelData.hx * (annSelection.width - width)
                y: modelData.hy * (annSelection.height - height)
            }
        }
    }

    Item {
        id: exportClip
        clip: true
        visible: false
        width: overlay.localSel ? overlay.localSel.w : 0
        height: overlay.localSel ? overlay.localSel.h : 0

        ShaderEffectSource {
            sourceItem: scene
            width: scene.width
            height: scene.height
            x: overlay.localSel ? -overlay.localSel.x : 0
            y: overlay.localSel ? -overlay.localSel.y : 0
            live: true
            recursive: false
        }
    }

    function grabExport(path, cb) {
        if (!overlay.localSel) { cb(false); return; }
        var scheduled = exportClip.grabToImage(function (result) {
            var ok = false;
            try { ok = result ? result.saveToFile(path) : false; }
            catch (e) { console.log("rishot: saveToFile failed: " + e); }
            if (cb) cb(ok);
        });
        if (!scheduled && cb) cb(false);
    }

    MouseArea {
        anchors.fill: parent
        enabled: overlay.ready
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.CrossCursor
        onPressed: (m) => overlay.pressedAt(m.x + overlay.sx, m.y + overlay.sy)
        onPositionChanged: (m) => {
            if (overlay.capturing) overlay.movedTo(m.x + overlay.sx, m.y + overlay.sy);
            else overlay.hovered(m.x + overlay.sx, m.y + overlay.sy);
        }
        onReleased: overlay.released()
    }

    /**
     * True when the named global edge of the selection lies on this screen
     * rather than being a clip artifact of intersectRect. A handle that drags
     * an off-screen edge would otherwise sit pinned at the monitor seam and,
     * once dragged, collapse that edge onto the seam; gating on the real edge
     * keeps each edge grabbable on exactly one screen.
     */
    function edgeOnScreen(role) {
        if (!globalSel) return false;
        var eps = 0.5;
        if (role.indexOf("l") >= 0 && globalSel.x < sx - eps) return false;
        if (role.indexOf("r") >= 0 && globalSel.x + globalSel.w > sx + width + eps) return false;
        if (role.indexOf("t") >= 0 && globalSel.y < sy - eps) return false;
        if (role.indexOf("b") >= 0 && globalSel.y + globalSel.h > sy + height + eps) return false;
        return true;
    }

    Item {
        id: resizeHandles
        anchors.fill: parent
        visible: overlay.ready && overlay.phase === "editing" && overlay.localSel !== null

        Repeater {
            model: [
                { role: "tl", ax: 0,   ay: 0,   corner: true,  cur: Qt.SizeFDiagCursor },
                { role: "t",  ax: 0.5, ay: 0,   corner: false, cur: Qt.SizeVerCursor },
                { role: "tr", ax: 1,   ay: 0,   corner: true,  cur: Qt.SizeBDiagCursor },
                { role: "r",  ax: 1,   ay: 0.5, corner: false, cur: Qt.SizeHorCursor },
                { role: "br", ax: 1,   ay: 1,   corner: true,  cur: Qt.SizeFDiagCursor },
                { role: "b",  ax: 0.5, ay: 1,   corner: false, cur: Qt.SizeVerCursor },
                { role: "bl", ax: 0,   ay: 1,   corner: true,  cur: Qt.SizeBDiagCursor },
                { role: "l",  ax: 0,   ay: 0.5, corner: false, cur: Qt.SizeHorCursor }
            ]

            Item {
                id: handle
                required property var modelData
                readonly property real cx: overlay.localSel
                    ? overlay.localSel.x + modelData.ax * overlay.localSel.w : 0
                readonly property real cy: overlay.localSel
                    ? overlay.localSel.y + modelData.ay * overlay.localSel.h : 0
                readonly property real visSize: modelData.corner ? 10 : 8
                readonly property bool real: { overlay.globalSel; return overlay.edgeOnScreen(modelData.role); }

                x: cx - 9
                y: cy - 9
                width: 18
                height: 18
                visible: real

                Rectangle {
                    anchors.centerIn: parent
                    width: handle.visSize
                    height: handle.visSize
                    radius: 1
                    color: overlay.vermilion
                    border.color: Qt.rgba(1, 1, 1, 0.85)
                    border.width: 1
                    antialiasing: true
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: handle.real
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: handle.modelData.cur
                    onPressed: overlay.resizeStarted(handle.modelData.role,
                        handle.cx + overlay.sx, handle.cy + overlay.sy)
                    onPositionChanged: (m) => {
                        if (pressed) overlay.resizeMoved(m.x + handle.x + overlay.sx,
                                                         m.y + handle.y + overlay.sy);
                    }
                    onReleased: overlay.resizeEnded()
                }
            }
        }
    }

    TextInput {
        id: textEdit
        readonly property bool mine: overlay.textEditing && overlay.draft
            && overlay.draft.type === "text" && overlay.localSel !== null
            && (overlay.draft.points[0].x >= overlay.sx) && (overlay.draft.points[0].x < overlay.sx + overlay.width)
            && (overlay.draft.points[0].y >= overlay.sy) && (overlay.draft.points[0].y < overlay.sy + overlay.height)
        visible: mine
        enabled: mine
        x: mine ? overlay.draft.points[0].x - overlay.sx : 0
        y: mine ? overlay.draft.points[0].y - overlay.sy : 0
        color: mine ? overlay.draft.color : "transparent"
        font.family: Theme.sansFamily
        font.pixelSize: mine ? overlay.draft.size : 16
        renderType: Text.NativeRendering
        cursorVisible: mine
        autoScroll: false
        onTextEdited: overlay.textChanged(text)
        onMineChanged: if (mine) { text = overlay.draft.text || ""; forceActiveFocus(); }
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { overlay.textCommitted(); e.accepted = true; }
            else if (e.key === Qt.Key_Escape) { e.accepted = false; }
        }
    }
}
