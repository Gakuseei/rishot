import { readFileSync, mkdtempSync, symlinkSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const launcher = join(root, "bin", "rishot");
const desktop = join(root, "rishot.desktop");
const catalogues = join(root, "src", "i18n");

let failed = 0;

/** Prints PASS, or FAIL, and counts the failure. */
function check(ok, msg) {
    if (ok) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg); }
}

// The launcher carries its own two languages because it must print usage and
// argument errors before it can find (or while it lacks) a config dir.
const script = readFileSync(launcher, "utf8");
const keys = (re) => {
    const out = new Set();
    let m;
    while ((m = re.exec(script)) !== null) out.add(m[1]);
    return out;
};
const esKeys = keys(/^\s*es:([a-z_]+)\)/gm);
const enKeys = keys(/^\s*\*:([a-z_]+)\)/gm);

check(esKeys.size > 0, "launcher has Spanish messages");
check(enKeys.size > 0, "launcher has English fallback messages");
check([...esKeys].sort().join() === [...enKeys].sort().join(),
    "every launcher message exists in both languages (" + [...esKeys].sort().join(", ") + ")");

// An absolute shell path keeps the minimal-PATH case below from failing to
// spawn before the launcher even runs.
const SH = "/bin/sh";

const run = (args, env) => spawnSync(SH, [launcher, ...args], {
    encoding: "utf8",
    env: { PATH: process.env.PATH, HOME: process.env.HOME || "/tmp", ...env }
});

const helpLine = (env) => {
    const r = run(["--help"], env);
    check(r.status === 0, "--help exits 0 with " + JSON.stringify(env));
    // A shell may warn about a locale the system has not generated; that is
    // not the launcher talking.
    check(!r.stderr.includes("rishot:"), "--help prints no error with " + JSON.stringify(env));
    return r.stdout.split("\n")[2] || "";
};

const spanishHelp = "uso: rishot [modo]";
const englishHelp = "usage: rishot [mode]";
const isEs = (env) => helpLine(env).startsWith(spanishHelp);
const isEn = (env) => helpLine(env).startsWith(englishHelp);

check(isEs({ LANG: "es_ES.UTF-8" }), "es_ES.UTF-8 -> Spanish");
check(isEs({ LANG: "es_AR.UTF-8" }), "es_AR.UTF-8 -> Spanish");
check(isEs({ LANG: "es_AR" }), "es_AR without a charset -> Spanish");
check(isEs({ LANG: "es-ES" }), "es-ES with a hyphen -> Spanish");
check(isEs({ LANG: "es_ES@euro" }), "es_ES@euro modifier -> Spanish");
check(isEs({ LANG: "ES_ES.UTF-8" }), "uppercase locale -> Spanish");
check(isEn({ LANG: "en_US.UTF-8" }), "en_US.UTF-8 -> English");
check(isEn({ LANG: "C" }), "C -> English");
check(isEn({ LANG: "POSIX" }), "POSIX -> English");
check(isEn({ LANG: "de_DE.UTF-8" }), "unknown locale -> English");
check(isEn({}), "no locale -> English");
check(isEs({ LANG: "es_ES.UTF-8", RISHOT_LANG: "" }), "empty RISHOT_LANG falls through to LANG");
check(isEn({ LANG: "" }), "empty LANG -> English");
check(isEs({ RISHOT_LANG: "es", LANG: "en_US.UTF-8" }), "RISHOT_LANG beats LANG");
check(isEn({ RISHOT_LANG: "en", LANG: "es_ES.UTF-8" }), "RISHOT_LANG=en beats LANG");
check(isEs({ RISHOT_LANG: "ES", LANG: "en_US.UTF-8" }), "uppercase RISHOT_LANG -> Spanish");
check(isEs({ RISHOT_LANG: " es ", LANG: "en_US.UTF-8" }), "RISHOT_LANG is trimmed like the overlay");
check(isEs({ RISHOT_LANG: "auto", LANG: "es_ES.UTF-8" }), "RISHOT_LANG=auto falls through");
check(isEs({ LANGUAGE: "es:en", LANG: "en_US.UTF-8" }), "LANGUAGE list picks the first match");
check(isEs({ LANGUAGE: "de: es", LANG: "en_US.UTF-8" }), "LANGUAGE list is trimmed");
check(isEs({ LC_ALL: "es_ES.UTF-8", LANG: "en_US.UTF-8" }), "LC_ALL beats LANG");
check(isEs({ LC_MESSAGES: "es_ES.UTF-8", LANG: "en_US.UTF-8" }), "LC_MESSAGES beats LANG");

// The Spanish help must keep one description column across every block.
const spanishHelpText = /cat <<'EOF'\n(rishot - captura[\s\S]*?)\nEOF/.exec(script);
check(spanishHelpText !== null, "launcher has a Spanish help block");
if (spanishHelpText !== null) {
    const columns = new Set();
    for (const line of spanishHelpText[1].split("\n")) {
        if (!line.startsWith("  ")) continue;
        const m = /\S( {2,})(\S)/.exec(line);
        if (m) columns.add(m.index + m[1].length + 1);
    }
    check(columns.size === 1, "Spanish help uses a single description column (" + [...columns].join(", ") + ")");
}

const badArg = (env) => run(["--nope"], env);
const badEs = badArg({ LANG: "es_ES.UTF-8" });
check(badEs.status === 2, "unknown argument exits 2");
check(badEs.stderr.split("\n")[0] === "rishot: argumento desconocido: --nope", "unknown argument is translated");
const badEn = badArg({ LANG: "en_US.UTF-8" });
check(badEn.stderr.split("\n")[0] === "rishot: unknown argument: --nope", "unknown argument keeps the English text");

const missingDir = (env) => run([], { RISHOT_CONFIG_DIR: "/nonexistent-rishot", ...env });
const missingEs = missingDir({ LANG: "es_ES.UTF-8" });
check(missingEs.status === 1, "missing config dir exits 1");
check(missingEs.stderr.split("\n")[0]
    === "rishot: no se pudo localizar el directorio de configuración (define RISHOT_CONFIG_DIR)",
    "missing config dir is translated");
const missingEn = missingDir({ LANG: "en_US.UTF-8" });
check(missingEn.stderr.split("\n")[0]
    === "rishot: could not locate the config dir (set RISHOT_CONFIG_DIR)",
    "missing config dir keeps the English text");

// --text needs tesseract; a PATH holding only tr reaches that check without
// touching the screen, and exercises the "--<option> needs <tool>" message.
const tr = spawnSync(SH, ["-c", "command -v tr"], { encoding: "utf8" }).stdout.trim();
if (tr !== "") {
    const dir = mkdtempSync(join(tmpdir(), "rishot-cli-"));
    try {
        symlinkSync(tr, join(dir, "tr"));
        const needs = (env) => spawnSync(SH, [launcher, "--text"], {
            encoding: "utf8",
            env: { PATH: dir, HOME: process.env.HOME || "/tmp", ...env }
        });
        const needsEs = needs({ LANG: "es_ES.UTF-8" });
        check(needsEs.status === 1, "missing tool exits 1");
        check(needsEs.stderr.split("\n")[0] === "rishot: --text necesita tesseract",
            "missing tool message is translated");
        check(needs({ LANG: "en_US.UTF-8" }).stderr.split("\n")[0] === "rishot: --text needs tesseract",
            "missing tool message keeps the English text");
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
} else {
    check(false, "tr is available to build a minimal PATH");
}

// The launcher notification title must not drift from the catalogue.
const en = JSON.parse(readFileSync(join(catalogues, "en.json"), "utf8"));
const es = JSON.parse(readFileSync(join(catalogues, "es.json"), "utf8"));
const branchText = (re) => { const m = re.exec(script); return m ? m[1] : null; };
check(branchText(/es:copied_summary\) printf '([^']*)'/) === es["notify.copied"],
    "launcher Spanish notification title matches notify.copied");
check(branchText(/\*:copied_summary\) printf '([^']*)'/) === en["notify.copied"],
    "launcher English notification title matches notify.copied");

const entry = readFileSync(desktop, "utf8");
const comment = /^Comment=(.+)$/m.exec(entry);
const commentEs = /^Comment\[es\]=(.+)$/m.exec(entry);
check(comment !== null && comment[1].trim() !== "", "desktop entry has an English Comment");
check(commentEs !== null && commentEs[1].trim() !== "", "desktop entry has a Spanish Comment[es]");
check(comment !== null && commentEs !== null && comment[1] !== commentEs[1],
    "desktop Comment[es] is actually translated");

console.log(failed === 0 ? "\nAll tests PASSED" : "\n" + failed + " test(s) FAILED");
process.exit(failed === 0 ? 0 : 1);
