pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: theme

    readonly property color vermilion: "#e0563b"
    readonly property color white:     "#ffffff"
    readonly property color idle:      "#c4ccda"
    readonly property color sep:       "#313a4d"

    readonly property color dim:        Qt.rgba(8 / 255, 10 / 255, 16 / 255, 0.62)
    readonly property color glassBg:    Qt.rgba(20 / 255, 24 / 255, 34 / 255, 0.92)
    readonly property color glassBorder: "#313a4d"
    readonly property color panelBg:    Qt.rgba(24 / 255, 28 / 255, 38 / 255, 0.97)
    readonly property color panelBorder: "#3a4456"

    readonly property color dimIcon: Qt.rgba(0.77, 0.80, 0.85, 0.35)
    readonly property color winFill: Qt.rgba(0.88, 0.34, 0.23, 0.16)
    readonly property color markerYellow: "#f5d020"

    readonly property var swatches: [
        "#e0563b", "#ffffff", "#1a1a1a", "#e23b3b", "#f2c14e", "#5bbf73", "#4f8fe0"
    ]

    readonly property string monoFamily: pick(
        ["JetBrains Mono", "JetBrainsMono Nerd Font", "DejaVu Sans Mono", "Liberation Mono"],
        "monospace")
    readonly property string sansFamily: pick(
        ["Inter", "Inter Display", "Noto Sans", "DejaVu Sans", "Liberation Sans"],
        "sans-serif")

    /**
     * Returns the first installed family from prefs, or the generic fallback
     * when none are present. Lets rishot ship without bundling fonts.
     */
    function pick(prefs, fallback) {
        var fams = Qt.fontFamilies();
        for (var i = 0; i < prefs.length; i++)
            if (fams.indexOf(prefs[i]) !== -1) return prefs[i];
        return fallback;
    }
}
