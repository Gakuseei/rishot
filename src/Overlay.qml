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

    function zoomBubbleRect(a, offX, offY) {
        var p0 = a.points[0], p1 = a.points[1];
        var sw = Math.abs(p1.x - p0.x), sh = Math.abs(p1.y - p0.y);
        var z = a.zoom || Config.zoomFactor;
        var bw = sw * z, bh = sh * z;
        var cx = Math.min(p0.x, p1.x) + sw / 2 + (offX || 0);
        var cy = Math.min(p0.y, p1.y) + sh / 2 + (offY || 0);
        return { x: cx - bw / 2, y: cy - bh / 2, w: bw, h: bh };
    }

    function selectionBox() {
        if (selectedIndex === null || !model
            || selectedIndex < 0 || selectedIndex >= model.items.length) return null;
        var a = model.items[selectedIndex];
        var off = moveOffset || { x: 0, y: 0 };
        if (a.type === "zoom") {
            var bb = zoomBubbleRect(a, off.x, off.y);
            var zpad = 6;
            return {
                x: bb.x - sx - zpad,
                y: bb.y - sy - zpad,
                w: bb.w + zpad * 2,
                h: bb.h + zpad * 2
            };
        }
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
        opacity: overlay.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        ScreencopyView {
            id: frozen
            anchors.fill: parent
            captureSource: overlay.screenData
            live: false
            paintCursor: false
        }

        readonly property real mosaicFactor: Config.mosaicFactor

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

        function zoomItems() {
            var src = overlay.model ? overlay.model.items : [];
            var out = [];
            for (var i = 0; i < src.length; i++)
                if (src[i] && src[i].type === "zoom") out.push(src[i]);
            if (overlay.draft && overlay.draft.type === "zoom") out.push(overlay.draft);
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
                    radius: Config.blurRadius
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

        Repeater {
            model: { overlay.annRevision; return scene.zoomItems(); }

            Item {
                id: zoomCell
                required property var modelData
                readonly property var a: modelData
                readonly property bool valid: a !== undefined && a !== null && a.points !== undefined && a.points.length >= 2
                readonly property bool selected: {
                    overlay.annRevision;
                    return overlay.selectedIndex !== null && overlay.model
                        && overlay.selectedIndex >= 0 && overlay.selectedIndex < overlay.model.items.length
                        && overlay.model.items[overlay.selectedIndex] === a;
                }
                readonly property var off: selected && overlay.moveOffset
                    ? overlay.moveOffset : { x: 0, y: 0 }

                readonly property real srcMinX: valid ? Math.min(a.points[0].x, a.points[1].x) : 0
                readonly property real srcMinY: valid ? Math.min(a.points[0].y, a.points[1].y) : 0
                readonly property real srcW: valid ? Math.abs(a.points[1].x - a.points[0].x) : 0
                readonly property real srcH: valid ? Math.abs(a.points[1].y - a.points[0].y) : 0
                readonly property real zf: (valid && a.zoom) ? a.zoom : Config.zoomFactor

                readonly property real srcLX: srcMinX - overlay.sx + off.x
                readonly property real srcLY: srcMinY - overlay.sy + off.y
                readonly property real bubW: srcW * zf
                readonly property real bubH: srcH * zf
                readonly property real corner: Math.min(bubW, bubH) * 0.08

                readonly property real srcCX: srcLX + srcW / 2
                readonly property real srcCY: srcLY + srcH / 2
                readonly property real bubLX: srcCX - bubW / 2
                readonly property real bubLY: srcCY - bubH / 2

                anchors.fill: parent
                visible: valid && srcW > 0 && srcH > 0

                Rectangle {
                    x: zoomCell.bubLX + 2
                    y: zoomCell.bubLY + 2
                    width: zoomCell.bubW
                    height: zoomCell.bubH
                    radius: zoomCell.corner
                    color: Qt.rgba(0, 0, 0, 0.28)
                    antialiasing: true
                }

                Item {
                    id: bubbleClip
                    x: zoomCell.bubLX
                    y: zoomCell.bubLY
                    width: zoomCell.bubW
                    height: zoomCell.bubH
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: zoomCell.bubW
                            height: zoomCell.bubH
                            radius: zoomCell.corner
                            antialiasing: true
                        }
                    }

                    ShaderEffectSource {
                        anchors.fill: parent
                        sourceItem: frozen
                        live: false
                        recursive: false
                        smooth: true
                        sourceRect: Qt.rect(zoomCell.srcLX, zoomCell.srcLY,
                                            zoomCell.srcW, zoomCell.srcH)
                    }
                }

                Rectangle {
                    x: zoomCell.bubLX
                    y: zoomCell.bubLY
                    width: zoomCell.bubW
                    height: zoomCell.bubH
                    radius: zoomCell.corner
                    color: "transparent"
                    border.color: overlay.vermilion
                    border.width: 2
                    antialiasing: true
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
        opacity: overlay.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Item {
        anchors.fill: parent
        visible: overlay.ready && overlay.localSel !== null
        opacity: overlay.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
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

        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.985
        transformOrigin: Item.Center
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

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
        id: drawArea
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
     *
     * Edge handles ("t", "b", "l", "r") name a single shared edge that can span
     * several monitors. Their handle sits at the global midpoint of that edge,
     * so gating only on edge presence would draw a duplicate, grabbable handle
     * on every monitor the edge crosses. The perpendicular midpoint check below
     * pins each edge handle to the one monitor that actually contains it.
     */
    function edgeOnScreen(role) {
        if (!globalSel) return false;
        var eps = 0.5;
        if (role.indexOf("l") >= 0 && globalSel.x < sx - eps) return false;
        if (role.indexOf("r") >= 0 && globalSel.x + globalSel.w > sx + width + eps) return false;
        if (role.indexOf("t") >= 0 && globalSel.y < sy - eps) return false;
        if (role.indexOf("b") >= 0 && globalSel.y + globalSel.h > sy + height + eps) return false;
        if (role === "t" || role === "b") {
            var mx = globalSel.x + globalSel.w / 2;
            if (mx < sx - eps || mx >= sx + width + eps) return false;
        }
        if (role === "l" || role === "r") {
            var my = globalSel.y + globalSel.h / 2;
            if (my < sy - eps || my >= sy + height + eps) return false;
        }
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

    Item {
        id: loupe
        enabled: false

        readonly property int box: 110
        readonly property real zoom: 8
        readonly property real sampleR: box / (2 * zoom)
        readonly property real margin: 24

        readonly property real cux: drawArea.mouseX
        readonly property real cuy: drawArea.mouseY
        readonly property bool flipX: cux + margin + box > overlay.width
        readonly property bool flipY: cuy + margin + box > overlay.height

        /**
         * Preferred offset places the loupe down-right of the cursor, flipping
         * to up/left near the far edges. The clamp is a floor for the flipped
         * branch: on a monitor narrower or shorter than the loupe plus margins
         * (e.g. a slim portrait secondary) the flipped offset would otherwise
         * run off the near edge. It never moves the loupe on a normally sized
         * screen, where the flip alone already keeps it inside.
         */
        function place(flip, cursor, extent) {
            var pos = flip ? cursor - margin - box : cursor + margin;
            return Math.max(0, Math.min(pos, extent - box));
        }

        width: box
        height: box
        x: place(flipX, cux, overlay.width)
        y: place(flipY, cuy, overlay.height)

        visible: overlay.ready && overlay.phase === "selecting" && drawArea.containsMouse
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Item {
            id: loupeClip
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: loupe.box
                    height: loupe.box
                    radius: 12
                    antialiasing: true
                }
            }

            Rectangle {
                anchors.fill: parent
                color: overlay.dimColor
            }

            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: frozen
                live: loupe.visible
                recursive: false
                smooth: false
                sourceRect: Qt.rect(loupe.cux - loupe.sampleR,
                                     loupe.cuy - loupe.sampleR,
                                     loupe.sampleR * 2,
                                     loupe.sampleR * 2)
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 1
                height: parent.height
                color: Qt.rgba(overlay.vermilion.r, overlay.vermilion.g, overlay.vermilion.b, 0.7)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                height: 1
                width: parent.width
                color: Qt.rgba(overlay.vermilion.r, overlay.vermilion.g, overlay.vermilion.b, 0.7)
            }

            Rectangle {
                anchors.centerIn: parent
                width: loupe.zoom
                height: loupe.zoom
                color: "transparent"
                border.color: overlay.vermilion
                border.width: 1
                antialiasing: true
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.color: overlay.vermilion
            border.width: 1.5
            antialiasing: true
        }

        Rectangle {
            anchors.horizontalCenter: loupeClip.horizontalCenter
            anchors.top: loupeClip.bottom
            anchors.topMargin: 6
            width: coordText.implicitWidth + 12
            height: coordText.implicitHeight + 6
            radius: 5
            color: Theme.glassBg
            border.color: Theme.glassBorder
            border.width: 1

            Text {
                id: coordText
                anchors.centerIn: parent
                text: Math.round(loupe.cux + overlay.sx) + ", " + Math.round(loupe.cuy + overlay.sy)
                color: overlay.vermilion
                font.family: Theme.monoFamily
                font.pixelSize: 11
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
