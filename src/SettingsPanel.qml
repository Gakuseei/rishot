import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "lib/keymap.js" as Keymap
import "Singletons"

Item {
    id: panel
    property string luaPath: ""
    property string hotkey: "—"
    property bool listening: false

    signal closeRequested()
    signal rebound()

    readonly property color glassBg: Theme.panelBg
    readonly property color glassBorder: Theme.panelBorder
    readonly property color vermilion: Theme.vermilion
    readonly property color idle: Theme.idle

    readonly property bool isHyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    readonly property bool useLua: panel.luaPath !== ""
    readonly property string hyprDir: Quickshell.env("HOME") + "/.config/hypr"
    readonly property string confPath: hyprDir + "/rishot.conf"
    readonly property string bindTarget: useLua ? panel.luaPath : confPath

    readonly property int arrow: 7
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight + arrow

    FileView {
        id: reader
        path: panel.bindTarget
        onLoaded: {
            var b = panel.useLua ? Keymap.parseBind(text()) : Keymap.parseConfBind(text());
            if (b) panel.hotkey = b;
        }
    }

    FileView {
        id: writer
        path: panel.bindTarget
        atomicWrites: true
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
     * Records the captured chord to the active target. With a lua keybind file
     * (Erik's Ricelin path) it writes an hl.bind line; otherwise it writes a
     * hyprlang bind to ~/.config/hypr/rishot.conf, after ensuring the dir
     * exists. Hyprland reload + rebound() fire from the writer's onSaved.
     */
    function applyBind(key, modifiers, text) {
        panel.listening = false;
        if (panel.useLua) {
            var bind = Keymap.bindString(key, modifiers, text);
            if (bind === null) return;
            panel.hotkey = bind;
            writer.setText(Keymap.luaFile(bind));
        } else {
            var line = Keymap.confFile(key, modifiers, text);
            if (line === null) return;
            mkHyprDir.running = true;
            panel.hotkey = Keymap.parseConfBind(line) || panel.hotkey;
            writer.setText(line);
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
                    Label { text: "Pixelate block size" }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: Config.mosaicFactor + "px"
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
                    visible: panel.isHyprland && !panel.useLua
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
            panel.applyBind(e.key, e.modifiers, e.text);
        }
    }
}
