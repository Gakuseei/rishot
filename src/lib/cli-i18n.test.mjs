import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const launcher = join(root, "bin", "rishot");
const desktop = join(root, "rishot.desktop");

let failed = 0;
function check(ok, msg) {
    if (ok) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg); }
}

// The launcher carries its own two languages because it ships as one file.
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

const run = (args, env) => spawnSync("sh", [launcher, ...args], {
    encoding: "utf8",
    env: { PATH: process.env.PATH, HOME: process.env.HOME || "/tmp", ...env }
});

const helpLine = (env) => {
    const r = run(["--help"], env);
    check(r.status === 0, "--help exits 0 with " + JSON.stringify(env));
    return r.stdout.split("\n")[2] || "";
};
const spanishHelp = "uso: rishot [modo]";
const englishHelp = "usage: rishot [mode]";

const isEs = (env) => helpLine(env).startsWith(spanishHelp);
const isEn = (env) => helpLine(env).startsWith(englishHelp);

check(isEs({ LANG: "es_ES.UTF-8" }), "es_ES.UTF-8 -> Spanish");
check(isEs({ LANG: "es_AR.UTF-8" }), "es_AR.UTF-8 -> Spanish");
check(isEn({ LANG: "en_US.UTF-8" }), "en_US.UTF-8 -> English");
check(isEn({ LANG: "C" }), "C -> English");
check(isEn({ LANG: "POSIX" }), "POSIX -> English");
check(isEn({ LANG: "de_DE.UTF-8" }), "unknown locale -> English");
check(isEn({}), "no locale -> English");
check(isEs({ RISHOT_LANG: "es", LANG: "en_US.UTF-8" }), "RISHOT_LANG beats LANG");
check(isEn({ RISHOT_LANG: "en", LANG: "es_ES.UTF-8" }), "RISHOT_LANG=en beats LANG");
check(isEs({ RISHOT_LANG: "auto", LANG: "es_ES.UTF-8" }), "RISHOT_LANG=auto falls through");
check(isEs({ LANGUAGE: "es:en", LANG: "en_US.UTF-8" }), "LANGUAGE list picks the first match");
check(isEs({ LC_ALL: "es_ES.UTF-8", LANG: "en_US.UTF-8" }), "LC_ALL beats LANG");
check(isEs({ LC_MESSAGES: "es_ES.UTF-8", LANG: "en_US.UTF-8" }), "LC_MESSAGES beats LANG");

const badArg = (env) => run(["--nope"], env);
const badEs = badArg({ LANG: "es_ES.UTF-8" });
check(badEs.status === 2, "unknown argument exits 2");
check(badEs.stderr.split("\n")[0] === "rishot: argumento desconocido: --nope", "unknown argument is translated");
const badEn = badArg({ LANG: "en_US.UTF-8" });
check(badEn.stderr.split("\n")[0] === "rishot: unknown argument: --nope", "unknown argument keeps the English text");

const missingDir = (env) => run([], { RISHOT_CONFIG_DIR: "/nonexistent-rishot", ...env });
check(missingDir({ LANG: "es_ES.UTF-8" }).stderr.split("\n")[0]
    === "rishot: no se pudo localizar el directorio de configuración (define RISHOT_CONFIG_DIR)",
    "missing config dir is translated");
check(missingDir({ LANG: "en_US.UTF-8" }).stderr.split("\n")[0]
    === "rishot: could not locate the config dir (set RISHOT_CONFIG_DIR)",
    "missing config dir keeps the English text");

const entry = readFileSync(desktop, "utf8");
const comment = /^Comment=(.+)$/m.exec(entry);
const commentEs = /^Comment\[es\]=(.+)$/m.exec(entry);
check(comment !== null && comment[1].trim() !== "", "desktop entry has an English Comment");
check(commentEs !== null && commentEs[1].trim() !== "", "desktop entry has a Spanish Comment[es]");
check(comment !== null && commentEs !== null && comment[1] !== commentEs[1],
    "desktop Comment[es] is actually translated");

console.log(failed === 0 ? "\nAll tests PASSED" : "\n" + failed + " test(s) FAILED");
process.exit(failed === 0 ? 0 : 1);
