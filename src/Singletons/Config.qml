pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: config

    property int mosaicFactor: 14
    property int blurRadius: 64

    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")) + "/rishot"
    readonly property string path: dir + "/config.json"

    property bool dirReady: false
    property bool savePending: false

    /**
     * Persists the current settings to config.path as pretty JSON. atomicWrites
     * writes a temp file inside config.dir then renames it, so the directory
     * must already exist or the write fails silently. On the very first run the
     * dir is created asynchronously, so a save() that arrives before it lands is
     * deferred (savePending) and flushed from mkdir's onExited.
     */
    function save() {
        if (!config.dirReady) {
            config.savePending = true;
            mkdir.running = true;
            return;
        }
        flush();
    }

    function flush() {
        store.setText(JSON.stringify({
            mosaicFactor: config.mosaicFactor,
            blurRadius: config.blurRadius
        }, null, 2));
    }

    FileView {
        id: store
        path: config.path
        atomicWrites: true
        onLoaded: {
            try {
                var c = JSON.parse(text());
                if (typeof c.mosaicFactor === "number") config.mosaicFactor = c.mosaicFactor;
                if (typeof c.blurRadius === "number") config.blurRadius = c.blurRadius;
            } catch (e) {
            }
        }
        onSaveFailed: (err) => console.log("rishot: config write failed: " + err)
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", config.dir]
        onExited: {
            config.dirReady = true;
            if (config.savePending) { config.savePending = false; config.flush(); }
        }
    }

    Component.onCompleted: mkdir.running = true
}
