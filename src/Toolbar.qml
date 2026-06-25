import QtQuick
import QtQuick.Layouts
import "Singletons"

Item {
    id: tb
    implicitWidth: glass.implicitWidth
    implicitHeight: glass.implicitHeight

    property string activeTool: "rect"
    property color activeColor: Theme.vermilion
    property int activeWidth: 4
    property bool activeFill: false
    property bool canUndo: false
    property bool canRedo: false
    property bool settingsOpen: false

    readonly property real gearCenterX: gear.x + row.x + gear.width / 2
    readonly property real colorCenterX: colorBtn.x + row.x + colorBtn.width / 2
    readonly property real widthCenterX: widthBtn.x + row.x + widthBtn.width / 2

    signal toolPicked(string tool)
    signal colorButtonClicked()
    signal widthButtonClicked()
    signal fillToggled()
    signal undoRequested()
    signal redoRequested()
    signal copyRequested()
    signal saveRequested()
    signal uploadRequested()
    signal settingsRequested()

    /**
     * Incremental drag delta since the last move, in pixels. The toolbar never
     * moves itself; shell.qml accumulates these into the toolbar offset so the
     * window owns the final position. dragReset() fires on a double-click of the
     * grip and asks shell.qml to drop any accumulated offset.
     */
    signal dragMoved(real dx, real dy)
    signal dragReset()

    readonly property color glassBg: Theme.glassBg
    readonly property color glassBorder: Theme.glassBorder
    readonly property color vermilion: Theme.vermilion
    readonly property color idle: Theme.idle
    readonly property color sep: Theme.sep

    /** Tool descriptors (id/icon/label/key); supplied by shell.qml. */
    property var tools: []

    property string hoverLabel: ""
    property string hoverKey: ""
    property real hoverCenterX: 0
    property bool hoverShown: false

    /** Latches the tooltip to the hovered button, anchored to its row-relative centre. */
    function showTip(label, key, centerX) {
        tb.hoverLabel = label;
        tb.hoverKey = key;
        tb.hoverCenterX = centerX;
        tb.hoverShown = true;
    }

    /** Clears the tooltip only if the button releasing hover still owns it. */
    function hideTip(label) {
        if (tb.hoverLabel === label) tb.hoverShown = false;
    }

    opacity: 0
    transform: Translate { id: rise; y: 6 }
    Component.onCompleted: appear.start()

    NumberAnimation {
        id: appear
        target: tb
        property: "opacity"
        from: 0
        to: 1
        duration: 140
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        running: appear.running
        target: rise
        property: "y"
        from: 6
        to: 0
        duration: 140
        easing.type: Easing.OutCubic
    }

    Rectangle {
        id: glass
        anchors.fill: parent
        radius: 10
        color: tb.glassBg
        border.color: tb.glassBorder
        border.width: 1
        implicitWidth: row.implicitWidth + 12
        implicitHeight: row.implicitHeight + 12

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 2

            Item {
                id: grip
                Layout.preferredWidth: 16
                Layout.preferredHeight: 32

                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    rowSpacing: 3
                    columnSpacing: 3
                    Repeater {
                        model: 6
                        Rectangle {
                            width: 2.5
                            height: 2.5
                            radius: 1.25
                            color: gripHover.hovered ? tb.idle : Qt.rgba(0.77, 0.80, 0.85, 0.85)
                        }
                    }
                }

                HoverHandler {
                    id: gripHover
                    cursorShape: gripDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }
                DragHandler {
                    id: gripDrag
                    target: null
                    property real lastX: 0
                    property real lastY: 0
                    onActiveChanged: {
                        if (active) {
                            lastX = centroid.scenePosition.x;
                            lastY = centroid.scenePosition.y;
                        }
                    }
                    onCentroidChanged: {
                        if (!active) return;
                        var sx = centroid.scenePosition.x;
                        var sy = centroid.scenePosition.y;
                        tb.dragMoved(sx - lastX, sy - lastY);
                        lastX = sx;
                        lastY = sy;
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onDoubleTapped: tb.dragReset()
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: tb.sep; Layout.leftMargin: 3; Layout.rightMargin: 3 }

            Repeater {
                model: tb.tools
                IconButton {
                    id: toolBtn
                    required property var modelData
                    icon: modelData.icon
                    active: tb.activeTool === modelData.id
                    onClicked: tb.toolPicked(modelData.id)

                    HoverHandler {
                        onHoveredChanged: hovered
                            ? tb.showTip(toolBtn.modelData.label, toolBtn.modelData.key,
                                         toolBtn.x + row.x + toolBtn.width / 2)
                            : tb.hideTip(toolBtn.modelData.label)
                    }
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: tb.sep; Layout.leftMargin: 3; Layout.rightMargin: 3 }

            Rectangle {
                id: colorBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 7
                color: colorMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                Rectangle {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    radius: 9
                    color: tb.activeColor
                    border.color: Qt.rgba(1, 1, 1, 0.7)
                    border.width: 1.5
                    scale: colorMa.pressed ? 0.9 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                }

                MouseArea {
                    id: colorMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: tb.colorButtonClicked()
                }
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Colour", "c", colorBtn.x + row.x + colorBtn.width / 2)
                        : tb.hideTip("Colour")
                }
            }

            Rectangle {
                id: widthBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 7
                color: widthMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                Rectangle {
                    anchors.centerIn: parent
                    width: tb.activeWidth * 1.6 + 5
                    height: tb.activeWidth * 1.6 + 5
                    radius: width / 2
                    color: tb.idle
                    Behavior on width { NumberAnimation { duration: 90 } }
                    scale: widthMa.pressed ? 0.9 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                }

                MouseArea {
                    id: widthMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: tb.widthButtonClicked()
                }
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Width", "w", widthBtn.x + row.x + widthBtn.width / 2)
                        : tb.hideTip("Width")
                }
            }

            Rectangle {
                id: fillBtn
                visible: tb.activeTool === "rect" || tb.activeTool === "ellipse"
                Layout.preferredWidth: visible ? 32 : 0
                Layout.preferredHeight: 32
                radius: 7
                color: fillMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 3
                    color: tb.activeFill ? tb.activeColor : "transparent"
                    border.color: tb.activeColor
                    border.width: 2
                    scale: fillMa.pressed ? 0.9 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                }

                MouseArea {
                    id: fillMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: tb.fillToggled()
                }
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Fill", "f", fillBtn.x + row.x + fillBtn.width / 2)
                        : tb.hideTip("Fill")
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: tb.sep; Layout.leftMargin: 3; Layout.rightMargin: 3 }

            IconButton {
                id: undoBtn
                icon: "undo"
                dim: !tb.canUndo
                onClicked: { if (tb.canUndo) tb.undoRequested(); }
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Undo", "Ctrl+Z", undoBtn.x + row.x + undoBtn.width / 2)
                        : tb.hideTip("Undo")
                }
            }
            IconButton {
                id: redoBtn
                icon: "redo"
                dim: !tb.canRedo
                onClicked: { if (tb.canRedo) tb.redoRequested(); }
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Redo", "Ctrl+Y", redoBtn.x + row.x + redoBtn.width / 2)
                        : tb.hideTip("Redo")
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: tb.sep; Layout.leftMargin: 3; Layout.rightMargin: 3 }

            IconButton {
                id: copyBtn
                icon: "copy"
                onClicked: tb.copyRequested()
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Copy", "Ctrl+C", copyBtn.x + row.x + copyBtn.width / 2)
                        : tb.hideTip("Copy")
                }
            }
            IconButton {
                id: saveBtn
                icon: "save"
                onClicked: tb.saveRequested()
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Save", "Ctrl+S", saveBtn.x + row.x + saveBtn.width / 2)
                        : tb.hideTip("Save")
                }
            }
            IconButton {
                id: uploadBtn
                icon: "upload"
                onClicked: tb.uploadRequested()
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Upload · public", "Ctrl+U", uploadBtn.x + row.x + uploadBtn.width / 2)
                        : tb.hideTip("Upload · public")
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: tb.sep; Layout.leftMargin: 3; Layout.rightMargin: 3 }

            IconButton {
                id: gear
                icon: "gear"
                active: tb.settingsOpen
                onClicked: tb.settingsRequested()
                HoverHandler {
                    onHoveredChanged: hovered
                        ? tb.showTip("Settings", ",", gear.x + row.x + gear.width / 2)
                        : tb.hideTip("Settings")
                }
            }
        }
    }

    Rectangle {
        id: tip
        visible: tb.hoverShown && tipLabel.text.length > 0
        radius: 6
        color: Theme.panelBg
        border.color: Theme.panelBorder
        border.width: 1
        width: tipRow.implicitWidth + 16
        height: tipRow.implicitHeight + 10
        y: glass.height + 6
        x: Math.max(0, Math.min(tb.hoverCenterX - width / 2, tb.width - width))
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 90 } }

        Row {
            id: tipRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                id: tipLabel
                text: tb.hoverLabel
                color: tb.idle
                font.family: Theme.monoFamily
                font.pixelSize: 12
            }
            Text {
                visible: tb.hoverKey.length > 0
                text: tb.hoverKey
                color: tb.vermilion
                font.family: Theme.monoFamily
                font.pixelSize: 12
            }
        }
    }
}
