import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "lib/keymap.js" as Keymap
import "Singletons"

Item {
    id: panel
    property string luaPath: ""
    property string hotkey: "unset"
    property bool listening: false

    signal closeRequested()
    signal rebound()

    readonly property color glassBg: Theme.panelBg
    readonly property color glassBorder: Theme.panelBorder
    readonly property color vermilion: Theme.vermilion
    readonly property color idle: Theme.idle

    readonly property bool isHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property string hyprDir: Quickshell.env("HOME") + "/.config/hypr"

    property string detectedFlavor: "conf"
    property bool detecting: false
    property var pendingChord: null
    property string currentText: ""

    readonly property string format: panel.luaPath !== ""
        ? (panel.luaPath.endsWith(".conf") ? "conf" : "lua")
        : panel.detectedFlavor
    readonly property string bindTarget: panel.luaPath !== ""
        ? panel.luaPath
        : panel.hyprDir + (panel.format === "conf" ? "/rishot.conf" : "/rishot.lua")

    readonly property int arrow: 7
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight + arrow

    transformOrigin: Item.Bottom
    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.96
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Process {
        id: detectProc
        command: ["sh", "-c",
            '[ -f "$1/hyprland.conf" ] && echo conf || { [ -f "$1/hyprland.lua" ] && echo lua || echo conf; }',
            "_", panel.hyprDir]
        stdout: StdioCollector { id: detectOut }
        onExited: {
            var f = detectOut.text.trim();
            if (f === "lua" || f === "conf") panel.detectedFlavor = f;
            panel.detecting = false;
            if (panel.pendingChord) {
                var c = panel.pendingChord;
                panel.pendingChord = null;
                panel.applyBind(c.key, c.modifiers);
            }
        }
    }

    Component.onCompleted: if (panel.isHyprland && panel.luaPath === "") {
        panel.detecting = true;
        detectProc.running = true;
    }

    FileView {
        id: reader
        path: panel.bindTarget
        blockLoading: true
        printErrors: false
        onLoaded: {
            panel.currentText = text();
            var b = panel.format === "lua" ? Keymap.parseBind(text()) : Keymap.parseConfBind(text());
            if (b) panel.hotkey = b;
        }
    }

    FileView {
        id: writer
        path: panel.bindTarget
        atomicWrites: true
        printErrors: false
        onSaved: { reloadProc.running = true; panel.rebound(); }
        onSaveFailed: (err) => console.log("rishot: keybind write failed: " + err)
    }

    Process {
        id: mkHyprDir
        command: ["mkdir", "-p", panel.hyprDir]
    }

    Process {
        id: reloadProc
        command: ["setsid", "-f", "sh", "-c", "sleep 0.5; hyprctl reload"]
    }

    /**
     * Records the captured chord to the active target. A bare modifier press is
     * ignored so the recorder keeps listening for the final key. In lua format
     * (native-lua Hyprland config, or Erik's Ricelin RISHOT_KEYBIND_FILE path) it
     * writes an hl.bind line; in conf format it writes a hyprlang bind, after
     * ensuring the hypr dir exists. If flavor autodetection has not finished yet
     * the chord is stashed and replayed from detectProc.onExited so it is never
     * written against a stale default flavor. Hyprland reload + rebound() fire
     * from the writer's onSaved.
     */
    function applyBind(key, modifiers) {
        var bind = Keymap.bindString(key, modifiers);
        if (bind === null) return;
        panel.listening = false;
        if (panel.detecting) {
            panel.pendingChord = { key: key, modifiers: modifiers };
            return;
        }
        panel.hotkey = bind;
        if (panel.format === "lua") {
            writer.setText(Keymap.replaceLuaBind(panel.currentText, bind));
        } else {
            mkHyprDir.running = true;
            writer.setText(Keymap.replaceConfBind(panel.currentText, key, modifiers));
        }
    }

    component Section: ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
    }

    component Label: Text {
        color: panel.idle
        font.family: Theme.monoFamily
        font.pixelSize: 12
    }

    component Toggle: Item {
        id: tg
        property bool checked: false
        signal toggled(bool v)

        implicitWidth: 38
        implicitHeight: 22

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: tg.checked ? panel.vermilion : Qt.rgba(1, 1, 1, 0.10)
            border.color: tg.checked ? panel.vermilion : panel.glassBorder
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
                width: 16
                height: 16
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: tg.checked ? parent.width - width - 3 : 3
                color: Theme.white
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }

        TapHandler { onTapped: tg.toggled(!tg.checked) }
    }

    component Slider: Item {
        id: slider
        property int from: 0
        property int to: 100
        property int value: 0
        signal moved(int v)
        signal committed(int v)

        Layout.fillWidth: true
        implicitHeight: 22

        readonly property real frac: to > from ? (value - from) / (to - from) : 0
        readonly property real travel: Math.max(0, width - knob.width)

        function valueAtX(px) {
            var f = travel > 0 ? Math.max(0, Math.min(1, (px - knob.width / 2) / travel)) : 0;
            return Math.round(from + f * (to - from));
        }

        function setFromX(px) {
            var v = slider.valueAtX(px);
            if (v !== value) slider.moved(v);
        }

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.10)

            Rectangle {
                width: parent.width * slider.frac
                height: parent.height
                radius: 2
                color: panel.vermilion
            }
        }

        Rectangle {
            id: knob
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: slider.frac * slider.travel
            color: drag.active ? panel.vermilion : Theme.white
            border.color: panel.vermilion
            border.width: 2
        }

        TapHandler {
            onTapped: (p) => {
                slider.setFromX(p.position.x);
                slider.committed(slider.valueAtX(p.position.x));
            }
        }
        DragHandler {
            id: drag
            target: null
            onCentroidChanged: if (active) slider.setFromX(centroid.position.x)
            onActiveChanged: if (!active) slider.committed(slider.value)
        }
    }

    Rectangle {
        id: card
        width: parent.width
        height: parent.height - panel.arrow
        radius: 10
        color: panel.glassBg
        border.color: panel.glassBorder
        border.width: 1
        implicitWidth: 240
        implicitHeight: content.implicitHeight + 24

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 14

            Section {
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Pixelate coarseness" }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: Config.mosaicFactor
                        color: panel.vermilion
                    }
                }
                Slider {
                    from: 4
                    to: 40
                    value: Config.mosaicFactor
                    onMoved: (v) => Config.mosaicFactor = v
                    onCommitted: Config.save()
                }
            }

            Section {
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Blur strength" }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: Config.blurRadius
                        color: panel.vermilion
                    }
                }
                Slider {
                    from: 8
                    to: 128
                    value: Config.blurRadius
                    onMoved: (v) => Config.blurRadius = v
                    onCommitted: Config.save()
                }
            }

            Section {
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Zoom factor" }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: "×" + Config.zoomFactor.toFixed(1)
                        color: panel.vermilion
                    }
                }
                Slider {
                    from: 15
                    to: 40
                    value: Math.round(Config.zoomFactor * 10)
                    onMoved: (v) => Config.zoomFactor = Math.round(v / 5) / 2
                    onCommitted: Config.save()
                }
            }

            Section {
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Save a copy on disk" }
                    Item { Layout.fillWidth: true }
                    Toggle {
                        checked: Config.copyToDisk
                        onToggled: (v) => { Config.copyToDisk = v; Config.save(); }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: "off keeps copy in the clipboard only"
                    color: Theme.dimIcon
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.sep
            }

            Section {
                Label { text: "Shortcut" }

                RowLayout {
                    visible: panel.isHyprland
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: panel.hotkey
                        color: panel.idle
                        font.family: Theme.monoFamily
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        id: recBtn
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: recLabel.implicitWidth + 24
                        radius: 6
                        color: panel.listening ? panel.vermilion
                            : (recHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06))
                        border.color: panel.listening ? panel.vermilion : panel.glassBorder
                        border.width: 1

                        Text {
                            id: recLabel
                            anchors.centerIn: parent
                            text: panel.listening ? "Press a key…" : "Record"
                            color: panel.listening ? Theme.white : panel.idle
                            font.family: Theme.monoFamily
                            font.pixelSize: 13
                        }

                        HoverHandler { id: recHover }
                        TapHandler {
                            onTapped: {
                                panel.listening = !panel.listening;
                                if (panel.listening) keyCatcher.forceActiveFocus();
                            }
                        }
                    }
                }

                Label {
                    visible: panel.isHyprland && panel.format === "lua"
                    Layout.fillWidth: true
                    text: 'add require("rishot") to hyprland.lua, then restart Hyprland to apply'
                    color: Theme.dimIcon
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Label {
                    visible: panel.isHyprland && panel.format === "conf"
                    Layout.fillWidth: true
                    text: "add: source = ~/.config/hypr/rishot.conf"
                    color: Theme.dimIcon
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Label {
                    visible: !panel.isHyprland
                    Layout.fillWidth: true
                    text: "bind 'rishot' to a key in your compositor config"
                    color: Theme.dimIcon
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Canvas {
        width: panel.arrow * 2
        height: panel.arrow
        anchors.top: card.bottom
        anchors.horizontalCenter: card.horizontalCenter
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width / 2, height);
            ctx.closePath();
            ctx.fillStyle = Theme.panelBg;
            ctx.fill();
        }
    }

    Item {
        id: keyCatcher
        focus: panel.visible
        Keys.onPressed: (e) => {
            e.accepted = true;
            if (e.key === Qt.Key_Escape) {
                if (panel.listening) panel.listening = false;
                else panel.closeRequested();
                return;
            }
            if (!panel.listening) return;
            panel.applyBind(e.key, e.modifiers);
        }
    }
}
