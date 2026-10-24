import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dir = join(here, "..", "i18n");

let failed = 0;
function check(ok, msg) {
    if (ok) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg); }
}

function readJson(name) {
    return JSON.parse(readFileSync(join(dir, name), "utf8"));
}

const manifest = readJson("languages.json");
const en = readJson("en.json");
const enKeys = Object.keys(en);

check(Array.isArray(manifest) && manifest.length > 0, "languages.json is a non-empty array");
check(manifest.some((l) => l.code === "en"), "manifest lists the English source catalogue");

const codes = manifest.map((l) => l.code);
for (const locale of manifest) {
    check(typeof locale.code === "string" && /^[a-z]{2}(_[A-Z]{2})?$/.test(locale.code),
        "manifest code is a language tag: " + locale.code);
    check(typeof locale.name === "string" && locale.name.trim() !== "",
        "manifest name is present: " + locale.code);
}

const files = readdirSync(dir).filter((f) => f.endsWith(".json") && f !== "languages.json");
check(files.length === codes.length,
    "one JSON per manifest entry (files: " + files.join(", ") + ")");

for (const code of codes) {
    check(files.includes(code + ".json"), "catalogue exists: " + code + ".json");
}

const placeholders = (text) => {
    const found = [];
    const re = /\{(\w+)\}/g;
    let m;
    while ((m = re.exec(text)) !== null) found.push(m[1]);
    return found.sort();
};

for (const key of enKeys) {
    check(/^[a-z0-9]+(_[a-z0-9]+)*(\.[a-z0-9]+(_[a-z0-9]+)*)*$/.test(key), "key shape: " + key);
    check(typeof en[key] === "string" && en[key].trim() !== "", "English value is not empty: " + key);
}

for (const code of codes) {
    if (!files.includes(code + ".json")) continue;
    const raw = readFileSync(join(dir, code + ".json"), "utf8");
    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (e) {
        check(false, code + ".json parses as JSON: " + e.message);
        continue;
    }
    check(true, code + ".json parses as JSON");

    const seen = new Set();
    for (const line of raw.split("\n")) {
        const m = /^\s*"([^"]+)"\s*:/.exec(line);
        if (!m) continue;
        check(!seen.has(m[1]), code + ".json has no duplicate key: " + m[1]);
        seen.add(m[1]);
    }

    for (const key of enKeys) {
        check(Object.prototype.hasOwnProperty.call(parsed, key),
            code + ".json keeps the key: " + key);
        if (!Object.prototype.hasOwnProperty.call(parsed, key)) continue;
        check(typeof parsed[key] === "string" && parsed[key].trim() !== "",
            code + ".json value is not empty: " + key);
        check(JSON.stringify(placeholders(parsed[key])) === JSON.stringify(placeholders(en[key])),
            code + ".json placeholders match: " + key);
    }

    for (const key of Object.keys(parsed)) {
        check(Object.prototype.hasOwnProperty.call(en, key),
            code + ".json has no key missing from en.json: " + key);
    }
}

console.log(failed === 0 ? "\nAll tests PASSED" : "\n" + failed + " test(s) FAILED");
process.exit(failed === 0 ? 0 : 1);
