import QtQuick
import QtQuick.Shapes
import "Singletons"

Item {
    id: icon

    property string name: ""
    property color tint: Theme.idle
    property real size: 18

    readonly property real vb: 24

    readonly property var defs: ({
        "select":  "M6 4l13 7-5.2 1.6-1.6 5.2z",
        "rect":    "M7 7h10a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1H7a1 1 0 0 1 -1 -1V8a1 1 0 0 1 1 -1z",
        "ellipse": "M21 12a9 6 0 0 1 -18 0a9 6 0 0 1 18 0z",
        "line":    "M5 19 19 5",
        "arrow":   "M5 19 19 5M12.5 5H19V11.5",
        "pen":     "M5 19l1.4-4.6L15.4 5l3.2 3.2L9 17.6 5 19z M13.6 6.8l3.2 3.2",
        "text":    "M6.5 7V6h11v1M12 6v13M10 19h4",
        "marker":  "M6 16.5l-1.6 4.1 4.1-1.6 9.4-9.4-2.5-2.5zM13.4 7.1l2.5 2.5",
        "step":    "M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16z M11 9.6l1.5-1.4v7.6",
        "blur":    "M12 4.4C8.4 9 6.4 12 6.4 15a5.6 5.6 0 0 0 11.2 0c0-3-2-6-5.6-10.6z",
        "pixelate": "M5 5h6v6H5z M13 5h6v6h-6z M5 13h6v6H5z M13 13h6v6h-6z",
        "undo":    "M7.6 8.4 4 12l3.6 3.6M4 12h10a5 5 0 0 1 0 10h-3",
        "redo":    "M16.4 8.4 20 12l-3.6 3.6M20 12H10a5 5 0 0 0 0 10h3",
        "copy":    "M9 8h10a1 1 0 0 1 1 1v10a1 1 0 0 1 -1 1H9a1 1 0 0 1 -1 -1V9a1 1 0 0 1 1 -1z M4.5 15.5V5a1 1 0 0 1 1 -1h10",
        "save":    "M6 4h10l4 4v12H6z M9 4v5h5V4 M8 20v-6h8v6",
        "upload":  "M12 15V4.5M8 8l4-4 4 4M5 20h14",
        "cancel":  "M6.5 6.5 17.5 17.5M17.5 6.5 6.5 17.5",
        "gear":    "M12 3L14.53 5.9L18.36 5.64L18.1 9.47L21 12L18.1 14.53L18.36 18.36L14.53 18.1L12 21L9.47 18.1L5.64 18.36L5.9 14.53L3 12L5.9 9.47L5.64 5.64L9.47 5.9z M12 9.3a2.7 2.7 0 1 0 0 5.4a2.7 2.7 0 1 0 0 -5.4z"
    })

    readonly property string d: defs[name] !== undefined ? defs[name] : ""

    Shape {
        id: glyph
        width: icon.vb
        height: icon.vb
        scale: icon.size / icon.vb
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: glyph.boundingRect.width > 0
            ? (icon.vb / 2 - (glyph.boundingRect.x + glyph.boundingRect.width / 2)) * glyph.scale
            : 0
        anchors.verticalCenterOffset: glyph.boundingRect.height > 0
            ? (icon.vb / 2 - (glyph.boundingRect.y + glyph.boundingRect.height / 2)) * glyph.scale
            : 0
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            strokeColor: icon.tint
            strokeWidth: 1.7
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.d }
        }
    }
}
