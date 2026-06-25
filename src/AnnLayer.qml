import QtQuick
import QtQuick.Shapes
import "Singletons"

Item {
    id: canvas

    required property int sx
    required property int sy
    property var model: null
    property var draft: null
    property int revision: 0
    property int commitRevision: 0
    property var selectedIndex: null
    property var moveOffset: null

    readonly property bool moving: selectedIndex !== null && moveOffset
        && (moveOffset.x !== 0 || moveOffset.y !== 0)

    function shifted(a, dx, dy) {
        var copy = {};
        for (var k in a) copy[k] = a[k];
        copy.points = [];
        for (var i = 0; i < a.points.length; i++)
            copy.points.push({ x: a.points[i].x + dx, y: a.points[i].y + dy });
        return copy;
    }

    /** Committed annotations, minus the one being dragged (drawn live by activeItems). */
    function committedItems() {
        var src = model ? model.items : [];
        if (!canvas.moving) return src.slice();
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (i !== selectedIndex) out.push(src[i]);
        return out;
    }

    /** The live draft plus, during a drag, the shifted copy of the selected item. */
    function activeItems() {
        var out = [];
        if (canvas.moving && model && selectedIndex >= 0 && selectedIndex < model.items.length)
            out.push(shifted(model.items[selectedIndex], moveOffset.x, moveOffset.y));
        if (draft) out.push(draft);
        return out;
    }

    function lp(a, i) {
        return Qt.point(a.points[i].x - sx, a.points[i].y - sy);
    }

    function polyPath(a) {
        var out = [];
        for (var i = 0; i < a.points.length; i++)
            out.push(Qt.point(a.points[i].x - sx, a.points[i].y - sy));
        return out;
    }

    function strokeColorOf(a) {
        if (a.type !== "marker") return a.color;
        var c = Qt.color(a.color);
        return Qt.rgba(c.r, c.g, c.b, 0.32);
    }

    function strokeWidthOf(a) {
        return a.type === "marker" ? a.width * 2.5 : a.width;
    }

    function ellipseGeom(a) {
        var p0 = lp(a, 0), p1 = lp(a, 1);
        return {
            cx: (p0.x + p1.x) / 2,
            cy: (p0.y + p1.y) / 2,
            rx: Math.abs(p1.x - p0.x) / 2,
            ry: Math.abs(p1.y - p0.y) / 2
        };
    }

    function arrowHead(a) {
        var p0 = lp(a, 0), p1 = lp(a, 1);
        var ang = Math.atan2(p1.y - p0.y, p1.x - p0.x);
        var len = Math.max(a.width * 5, 22);
        var spread = 0.45;
        return {
            tip: p1,
            a: Qt.point(p1.x - len * Math.cos(ang - spread), p1.y - len * Math.sin(ang - spread)),
            b: Qt.point(p1.x - len * Math.cos(ang + spread), p1.y - len * Math.sin(ang + spread))
        };
    }

    Component {
        id: annDelegate

        Item {
            id: cell
            required property var modelData
            readonly property var a: modelData
            readonly property bool present: a !== undefined && a !== null && a.points !== undefined
            readonly property bool isText: present && a.type === "text" && a.points.length >= 1
            readonly property bool isStep: present && a.type === "step" && a.points.length >= 1
            readonly property bool valid: present && a.points.length >= 2
                && a.type !== "blur" && a.type !== "pixelate" && a.type !== "zoom"
            readonly property string kind: valid ? a.type : (isText ? "text" : (isStep ? "step" : ""))
            anchors.fill: parent
            visible: valid || isText || isStep

            Rectangle {
                visible: cell.valid && cell.kind === "rect"
                x: cell.valid ? Math.min(cell.a.points[0].x, cell.a.points[1].x) - canvas.sx : 0
                y: cell.valid ? Math.min(cell.a.points[0].y, cell.a.points[1].y) - canvas.sy : 0
                width: cell.valid ? Math.abs(cell.a.points[1].x - cell.a.points[0].x) : 0
                height: cell.valid ? Math.abs(cell.a.points[1].y - cell.a.points[0].y) : 0
                color: (cell.valid && cell.a.filled === true) ? cell.a.color : "transparent"
                border.color: cell.valid ? cell.a.color : "transparent"
                border.width: cell.valid ? cell.a.width : 0
                antialiasing: true
            }

            Rectangle {
                visible: cell.valid && cell.kind === "marker"
                x: cell.valid ? Math.min(cell.a.points[0].x, cell.a.points[1].x) - canvas.sx : 0
                y: cell.valid ? Math.min(cell.a.points[0].y, cell.a.points[1].y) - canvas.sy : 0
                width: cell.valid ? Math.abs(cell.a.points[1].x - cell.a.points[0].x) : 0
                height: cell.valid ? Math.abs(cell.a.points[1].y - cell.a.points[0].y) : 0
                radius: Math.min(width, height) * 0.18
                color: {
                    if (!cell.valid) return "transparent";
                    var c = Qt.color(cell.a.color);
                    return Qt.rgba(c.r, c.g, c.b, 0.32);
                }
                antialiasing: true
            }

            Shape {
                id: polyShape
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                visible: cell.valid && (cell.kind === "line" || cell.kind === "arrow"
                    || cell.kind === "pen")

                ShapePath {
                    strokeColor: cell.valid ? canvas.strokeColorOf(cell.a) : "transparent"
                    strokeWidth: cell.valid ? canvas.strokeWidthOf(cell.a) : 0
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: cell.valid ? canvas.lp(cell.a, 0).x : 0
                    startY: cell.valid ? canvas.lp(cell.a, 0).y : 0
                    PathPolyline {
                        path: {
                            if (!cell.valid) return [];
                            if (cell.kind === "pen") return canvas.polyPath(cell.a);
                            return [canvas.lp(cell.a, 0), canvas.lp(cell.a, 1)];
                        }
                    }
                }
            }

            Shape {
                id: ellShape
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                visible: cell.valid && cell.kind === "ellipse"
                readonly property var eg: (cell.valid && cell.kind === "ellipse") ? canvas.ellipseGeom(cell.a) : null

                ShapePath {
                    strokeColor: cell.valid ? canvas.strokeColorOf(cell.a) : "transparent"
                    strokeWidth: cell.valid ? canvas.strokeWidthOf(cell.a) : 0
                    fillColor: (cell.valid && cell.a.filled === true) ? cell.a.color : "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: ellShape.eg ? ellShape.eg.cx - ellShape.eg.rx : 0
                    startY: ellShape.eg ? ellShape.eg.cy : 0
                    PathArc {
                        x: ellShape.eg ? ellShape.eg.cx + ellShape.eg.rx : 0
                        y: ellShape.eg ? ellShape.eg.cy : 0
                        radiusX: ellShape.eg ? ellShape.eg.rx : 0
                        radiusY: ellShape.eg ? ellShape.eg.ry : 0
                    }
                    PathArc {
                        x: ellShape.eg ? ellShape.eg.cx - ellShape.eg.rx : 0
                        y: ellShape.eg ? ellShape.eg.cy : 0
                        radiusX: ellShape.eg ? ellShape.eg.rx : 0
                        radiusY: ellShape.eg ? ellShape.eg.ry : 0
                    }
                }
            }

            Shape {
                id: headShape
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                visible: cell.valid && cell.kind === "arrow"
                readonly property var pts: (cell.valid && cell.kind === "arrow") ? canvas.arrowHead(cell.a) : null

                ShapePath {
                    strokeColor: cell.valid ? cell.a.color : "transparent"
                    strokeWidth: cell.valid ? cell.a.width : 0
                    fillColor: cell.valid ? cell.a.color : "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: headShape.pts ? headShape.pts.tip.x : 0
                    startY: headShape.pts ? headShape.pts.tip.y : 0
                    PathLine { x: headShape.pts ? headShape.pts.a.x : 0; y: headShape.pts ? headShape.pts.a.y : 0 }
                    PathLine { x: headShape.pts ? headShape.pts.b.x : 0; y: headShape.pts ? headShape.pts.b.y : 0 }
                    PathLine { x: headShape.pts ? headShape.pts.tip.x : 0; y: headShape.pts ? headShape.pts.tip.y : 0 }
                }
            }

            Text {
                visible: cell.isText && cell.a !== canvas.draft
                x: cell.isText ? cell.a.points[0].x - canvas.sx : 0
                y: cell.isText ? cell.a.points[0].y - canvas.sy : 0
                text: cell.isText ? (cell.a.text || "") : ""
                color: cell.isText ? cell.a.color : "transparent"
                font.family: Theme.sansFamily
                font.pixelSize: cell.isText ? cell.a.size : 16
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
            }

            Rectangle {
                readonly property real d: cell.isStep ? (cell.a.size || 32) : 0
                visible: cell.isStep
                width: d
                height: d
                radius: d / 2
                x: cell.isStep ? canvas.lp(cell.a, 0).x - d / 2 : 0
                y: cell.isStep ? canvas.lp(cell.a, 0).y - d / 2 : 0
                color: cell.isStep ? cell.a.color : "transparent"
                antialiasing: true

                Text {
                    anchors.centerIn: parent
                    text: cell.isStep ? String(cell.a.n) : ""
                    color: Theme.stepText
                    font.family: Theme.sansFamily
                    font.bold: true
                    font.pixelSize: parent.d * 0.55
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }
            }
        }
    }

    Repeater {
        model: { canvas.commitRevision; canvas.moving; return canvas.committedItems(); }
        delegate: annDelegate
    }

    Repeater {
        model: { canvas.revision; return canvas.activeItems(); }
        delegate: annDelegate
    }
}
