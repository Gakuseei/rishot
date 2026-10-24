import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { normalizeLocale, resolveLocale, lookup, format, translate } = require("./i18n.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

// normalizeLocale strips charset/modifier, normalizes separators, drops the
// POSIX pseudo-locales so they fall through to the next candidate.
eq(normalizeLocale("es_ES.UTF-8"), "es_ES", "charset stripped");
eq(normalizeLocale("es-AR"), "es_AR", "hyphen becomes underscore");
eq(normalizeLocale("es_ES@euro"), "es_ES", "modifier stripped");
eq(normalizeLocale("C"), "", "C is no locale");
eq(normalizeLocale("POSIX"), "", "POSIX is no locale");
eq(normalizeLocale(""), "", "empty is no locale");
eq(normalizeLocale(null), "", "null is no locale");

const A = ["en", "es", "es_AR"];

eq(resolveLocale({ LANG: "es_ES.UTF-8" }, A), "es", "LANG es_ES matches es");
eq(resolveLocale({ LANG: "es_AR.UTF-8" }, A), "es_AR", "exact region wins over base");
eq(resolveLocale({ RISHOT_LANG: "en", LANG: "es_ES.UTF-8" }, A), "en", "RISHOT_LANG beats LANG");
eq(resolveLocale({ LANGUAGE: "fr:es", LANG: "en_US.UTF-8" }, A), "es", "LANGUAGE list picks the first available");
eq(resolveLocale({ LC_ALL: "es_ES.UTF-8", LANG: "en_US.UTF-8" }, A), "es", "LC_ALL beats LANG");
eq(resolveLocale({ LC_MESSAGES: "es_ES.UTF-8", LANG: "en_US.UTF-8" }, A), "es", "LC_MESSAGES beats LANG");
eq(resolveLocale({ RISHOT_LANG: "auto", LANG: "es_ES.UTF-8" }, A), "es", "RISHOT_LANG=auto falls through");
eq(resolveLocale({ LANG: "de_DE.UTF-8" }, A), "en", "unknown locale falls back to en");
eq(resolveLocale({}, A), "en", "no env falls back to en");
eq(resolveLocale({ LANG: "de_DE.UTF-8" }, ["es", "fr"]), "es", "no en available uses the first catalogue");
eq(resolveLocale({ LANG: "es_ES.UTF-8" }, []), "en", "empty catalogue list falls back to en");
eq(resolveLocale({ RISHOT_LANG: "es" }, A), "es", "RISHOT_LANG alone works");

const en = { "tool.rect": "Rectangle", "notify.saved": "Screenshot saved", "greet": "Hi {name}" };
const es = { "tool.rect": "Rectángulo", "greet": "Hola {name}" };

eq(lookup("tool.rect", es), "Rectángulo", "lookup finds the active string");
eq(lookup("notify.saved", es), null, "lookup does not fall back by itself");
eq(lookup("missing.key", es), null, "lookup returns null when both catalogues miss");
eq(lookup("greet", es), "Hola {name}", "lookup returns the raw template");

eq(format("Hi {name}", { name: "Ada" }), "Hi Ada", "format substitutes a parameter");
eq(format("{a} and {b}", { a: 1, b: "two" }), "1 and two", "format handles numbers");
eq(format("Hi {name}", null), "Hi {name}", "format without params keeps placeholders");
eq(format("Hi {name}", {}), "Hi {name}", "format with an empty map keeps placeholders");
eq(format("Hi {name}", { other: 1 }), "Hi {name}", "format keeps unknown placeholders");
eq(format("{x}{x}", { x: "a" }), "aa", "format replaces repeated placeholders");

const missing = [];
const warn = (key) => missing.push(key);
eq(translate("greet", { name: "Ada" }, es, en, warn), "Hola Ada", "translate picks the active template");
eq(translate("notify.saved", null, es, en, warn), "Screenshot saved", "translate falls back to English");
eq(translate("nope", null, es, en, warn), "nope", "translate returns the key when nothing matches");
eq(translate("nope", null, es, en, warn), "nope", "second miss stays a key");
eq(missing, ["nope"], "missing keys warn once");

console.log(failed === 0 ? "\nAll tests PASSED" : "\n" + failed + " test(s) FAILED");
process.exit(failed === 0 ? 0 : 1);
