pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/i18n.js" as Lib

/**
 * Translation catalogue loader.
 *
 * Quickshell never installs a QTranslator, so qsTr() cannot resolve anything;
 * rishot ships plain JSON catalogues under src/i18n and this singleton picks
 * the active one. Every consumer reads strings through tr(); the language is
 * the settings override (Config.language) when it names a known catalogue,
 * otherwise the environment decides (RISHOT_LANG, then LANGUAGE, LC_ALL,
 * LC_MESSAGES, LANG) and finally English.
 */
Singleton {
    id: i18n

    /** Bumps when the active catalogue finishes loading so bindings re-evaluate. */
    property int revision: 0

    readonly property var languages: {
        if (String(manifestView.path) === "") return [];
        var raw = manifestView.text();
        if (!raw) return [];
        try {
            var list = JSON.parse(raw);
            return Array.isArray(list) ? list : [];
        } catch (e) {
            console.warn("rishot: languages.json parse failed: " + e);
            return [];
        }
    }

    readonly property var available: {
        var codes = [];
        for (var i = 0; i < languages.length; i++) codes.push(languages[i].code);
        return codes;
    }

    readonly property var environment: ({
        RISHOT_LANG: env("RISHOT_LANG"),
        LANGUAGE: env("LANGUAGE"),
        LC_ALL: env("LC_ALL"),
        LC_MESSAGES: env("LC_MESSAGES"),
        LANG: env("LANG")
    })

    /** Active catalogue code: the settings pick, else the system locale, else en. */
    readonly property string lang: {
        var forced = Config.language;
        if (forced !== "" && available.indexOf(forced) >= 0) return forced;
        return Lib.resolveLocale(environment, available);
    }

    readonly property var fallbackCatalog: parse(fallbackView, "en.json")
    readonly property var catalog: lang === Lib.FALLBACK_LOCALE
        ? fallbackCatalog
        : parse(activeView, lang + ".json")

    /**
     * Looks a key up in the active catalogue, then English, then the key
     * itself. Missing keys are logged once by lib/i18n.js. Reading revision
     * here makes every binding that calls tr() follow a language change.
     */
    function tr(key, params) {
        revision;
        return Lib.translate(key, params || null, catalog, fallbackCatalog, warnMissing);
    }

    function env(name) {
        var value = Quickshell.env(name);
        return value === undefined || value === null ? "" : String(value);
    }

    function parse(view, name) {
        if (String(view.path) === "") return ({});
        // blockLoading makes this first read wait for the catalogue; later
        // reads are cheap and the catalogues change only on a language switch.
        var raw = view.text();
        if (!raw) return ({});
        try {
            var data = JSON.parse(raw);
            return data && typeof data === "object" ? data : ({});
        } catch (e) {
            console.warn("rishot: i18n/" + name + " parse failed: " + e);
            return ({});
        }
    }

    function warnMissing(key) {
        console.warn("rishot: missing translation key: " + key);
    }

    FileView {
        id: manifestView
        path: Qt.resolvedUrl("../i18n/languages.json")
        blockLoading: true
        printErrors: false
        onLoadFailed: (error) => console.warn("rishot: i18n/languages.json load failed: " + error)
    }

    FileView {
        id: fallbackView
        path: Qt.resolvedUrl("../i18n/en.json")
        blockLoading: true
        printErrors: false
        onLoaded: i18n.revision++
        onLoadFailed: (error) => console.warn("rishot: i18n/en.json load failed: " + error)
    }

    FileView {
        id: activeView
        path: i18n.lang === Lib.FALLBACK_LOCALE
            ? ""
            : Qt.resolvedUrl("../i18n/" + i18n.lang + ".json")
        blockLoading: true
        printErrors: false
        onLoaded: i18n.revision++
        onLoadFailed: (error) => console.warn("rishot: i18n/" + i18n.lang + ".json load failed: " + error)
    }
}
