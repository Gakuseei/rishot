/**
 * Locale resolution and catalogue lookup for rishot's JSON translations.
 *
 * Quickshell loads a plain QQmlEngine and never installs a QTranslator, so
 * qsTr() cannot resolve anything. The catalogue is therefore plain JSON read
 * at runtime; this module holds the parts that need no QML so they can be
 * unit tested with node.
 */

var FALLBACK_LOCALE = "en";

// Highest precedence first. RISHOT_LANG is rishot's own override; LANGUAGE is
// a colon separated preference list; the POSIX variables follow the usual
// LC_ALL > LC_MESSAGES > LANG order.
var LOCALE_SOURCES = ["RISHOT_LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"];

/**
 * Reduces a locale string to "language[_REGION]": drops the charset and the
 * @modifier, turns dashes into underscores and maps the POSIX pseudo-locales
 * to the empty string so they never match a catalogue.
 */
function normalizeLocale(raw) {
    if (typeof raw !== "string") return "";
    var s = raw.trim();
    if (s === "") return "";
    var at = s.indexOf("@");
    if (at >= 0) s = s.substring(0, at);
    var dot = s.indexOf(".");
    if (dot >= 0) s = s.substring(0, dot);
    s = s.replace(/-/g, "_");
    if (s === "C" || s === "POSIX") return "";
    return s;
}

/**
 * Returns the catalogue code a normalized locale maps to: an exact match
 * first (es_AR), then the bare language (es). Missing returns "".
 */
function matchLocale(norm, available) {
    if (norm === "") return "";
    var lower = norm.toLowerCase();
    var base = lower.split("_")[0];
    var i;
    for (i = 0; i < available.length; i++)
        if (String(available[i]).toLowerCase() === lower) return available[i];
    for (i = 0; i < available.length; i++)
        if (String(available[i]).toLowerCase() === base) return available[i];
    return "";
}

/**
 * Picks the catalogue code to load. env is a plain object of environment
 * variables (missing entries are fine, undefined is fine). Earlier sources
 * win; an unknown value just falls through to the next source. When nothing
 * matches, English wins, or the first available catalogue when English is
 * not shipped.
 */
function resolveLocale(env, available) {
    var codes = available || [];
    var e = env || {};
    for (var s = 0; s < LOCALE_SOURCES.length; s++) {
        var raw = e[LOCALE_SOURCES[s]];
        if (typeof raw !== "string" || raw === "") continue;
        var parts = raw.split(":");
        for (var p = 0; p < parts.length; p++) {
            var hit = matchLocale(normalizeLocale(parts[p]), codes);
            if (hit !== "") return hit;
        }
    }
    for (var i = 0; i < codes.length; i++)
        if (String(codes[i]).toLowerCase() === FALLBACK_LOCALE) return codes[i];
    return codes.length > 0 ? codes[0] : FALLBACK_LOCALE;
}

/**
 * Reads key from a parsed catalogue. Returns null when the key is absent or
 * does not hold a string, so the caller can try the fallback catalogue.
 */
function lookup(key, catalog) {
    if (!catalog || typeof catalog !== "object") return null;
    if (!Object.prototype.hasOwnProperty.call(catalog, key)) return null;
    var value = catalog[key];
    return typeof value === "string" ? value : null;
}

/**
 * Replaces {name} placeholders with params.name. Unknown placeholders stay
 * verbatim so a malformed catalogue is visible instead of silently dropping
 * text.
 */
function format(text, params) {
    if (typeof text !== "string") return text;
    if (!params) return text;
    return text.replace(/\{(\w+)\}/g, function (all, name) {
        return Object.prototype.hasOwnProperty.call(params, name) ? String(params[name]) : all;
    });
}

var warned = {};

/**
 * Resolves key through the active catalogue, then English, then the key
 * itself. onMissing is called once per key so a binding re-evaluation cannot
 * flood the log.
 */
function translate(key, params, catalog, fallback, onMissing) {
    var text = lookup(key, catalog);
    if (text === null) text = lookup(key, fallback);
    if (text === null) {
        if (typeof onMissing === "function" && !warned[key]) {
            warned[key] = true;
            onMissing(key);
        }
        text = key;
    }
    return format(text, params);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        FALLBACK_LOCALE: FALLBACK_LOCALE,
        normalizeLocale: normalizeLocale,
        resolveLocale: resolveLocale,
        lookup: lookup,
        format: format,
        translate: translate
    };
}
