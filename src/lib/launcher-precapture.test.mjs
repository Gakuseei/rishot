import { mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

// Drives bin/rishot against stub qs, grim and spectacle on a PATH that holds
// nothing else the launcher could reach for, so no test touches a real screen.

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const launcher = join(root, "bin", "rishot");
const SH = "/bin/sh";

let failed = 0;

/** Prints PASS, or FAIL, and counts the failure. */
function check(ok, msg) {
    if (ok) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg); }
}

const realPath = process.env.PATH;
const which = (t) => spawnSync(SH, ["-c", 'command -v "$1"', "_", t], { encoding: "utf8" }).stdout.trim();
const tools = ["cat", "dirname", "env", "flock", "ls", "mkdir", "mktemp", "od", "readlink", "rm", "tr"];
const missing = tools.filter((t) => which(t) === "");
if (missing.length > 0) {
    console.log("FAIL launcher test needs " + missing.join(", "));
    process.exit(1);
}

// Every stub logs one line to $STUB_LOG and keeps the real PATH for itself.
const stubs = {
    qs: `
printf 'qs frozen=%s outfile=%s width=%s\\n' "\${RISHOT_FROZEN_PNG-unset}" "\${RISHOT_OUTFILE-}" "\${RISHOT_FROZEN_WIDTH-unset}" >>"$STUB_LOG"
if [ -n "\${RISHOT_FROZEN_PNG:-}" ]; then
	printf 'qs bytes=%s mode=%s\\n' "$(wc -c <"$RISHOT_FROZEN_PNG" | tr -d ' ')" \\
		"$(ls -ld "$(dirname "$RISHOT_FROZEN_PNG")" | cut -c1-10)" >>"$STUB_LOG"
fi
[ -z "\${RISHOT_OUTFILE:-}" ] || printf 'PNGDATA' >"$RISHOT_OUTFILE"
case "\${STUB_QS:-}" in
	fail) exit 3 ;;
	term) kill -TERM "$PPID"; sleep 5 </dev/null >/dev/null 2>&1; echo "qs survived" >>"$STUB_LOG" ;;
esac
exit 0`,
    grim: `
printf 'grim %s\\n' "$*" >>"$STUB_LOG"
echo "grim stdout noise"
for last; do :; done
case "\${STUB_GRAB:-}" in fail) exit 1 ;; empty) : >"$last"; exit 0 ;; junk) printf 'x' >"$last"; exit 0 ;; esac
printf '\\211PNG\\r\\n\\032\\n\\000\\000\\000\\rIHDR\\000\\000\\017\\240\\000\\000\\012\\000' >"$last"`,
    spectacle: `
printf 'spectacle %s\\n' "$*" >>"$STUB_LOG"
for last; do :; done
printf '\\211PNG\\r\\n\\032\\n\\000\\000\\000\\rIHDR\\000\\000\\017\\240\\000\\000\\012\\000' >"$last"`
};

/**
 * Runs the launcher in a fresh runtime dir with the named stubs on PATH.
 * Returns the spawn result plus the stub log lines and what the runtime dir
 * still holds afterwards.
 */
function launch({ args = [], env = {}, have = ["qs", "grim"], wrap = null } = {}) {
    const box = mkdtempSync(join(tmpdir(), "rishot-pre-"));
    try {
        const bin = join(box, "bin");
        const run = join(box, "run");
        const conf = join(box, "conf");
        mkdirSync(bin);
        mkdirSync(run, { mode: 0o700 });
        mkdirSync(conf);
        writeFileSync(join(conf, "shell.qml"), "");
        for (const t of tools) symlinkSync(which(t), join(bin, t));
        for (const s of have)
            writeFileSync(join(bin, s), `#!/bin/sh\nPATH=${JSON.stringify(realPath)}\n${stubs[s]}\n`, { mode: 0o755 });
        const log = join(box, "log");
        writeFileSync(log, "");
        const cmd = wrap ? ["-c", wrap, "_", launcher, ...args] : [launcher, ...args];
        const r = spawnSync(SH, cmd, {
            encoding: "utf8",
            env: {
                PATH: bin, HOME: box, LANG: "C", XDG_RUNTIME_DIR: run,
                RISHOT_CONFIG_DIR: conf, STUB_LOG: log, ...env
            }
        });
        const lines = readFileSync(log, "utf8").split("\n").filter((l) => l !== "");
        const left = readdirSync(run).filter((n) => n !== "rishot.lock");
        return { ...r, lines, left, run };
    } finally {
        rmSync(box, { recursive: true, force: true });
    }
}

const grims = (r) => r.lines.filter((l) => l.startsWith("grim "));
const qsLine = (r) => r.lines.find((l) => l.startsWith("qs frozen=")) || "";
const frozenOf = (r) => (/^qs frozen=(\S*)/.exec(qsLine(r)) || [])[1];

// The default path: grim runs once, before qs, into a private dir qs is told about.
{
    const r = launch();
    check(r.status === 0, "launcher exits 0 after qs");
    check(grims(r).length === 1, "grim runs exactly once");
    check(r.lines[0].startsWith("grim "), "grim runs before qs starts");
    const f = frozenOf(r);
    check(typeof f === "string" && new RegExp("^" + r.run + "/rishot\\.[^/]{6}/frozen\\.png$").test(f),
        "frozen PNG lives in a mktemp dir under XDG_RUNTIME_DIR (" + f + ")");
    check(grims(r)[0] === "grim -l 1 " + f, "grim writes the exact file qs is handed, lightly compressed");
    check(r.lines.includes("qs bytes=24 mode=drwx------"), "qs can read the PNG and its dir is 0700");
    check(/ width=4000$/.test(qsLine(r)), "qs gets the PNG pixel width read from its IHDR");
    check(r.left.length === 0, "scratch dir is removed after a normal exit");
    check(!r.stdout.includes("noise"), "grim output stays off the launcher's stdout");
}

check(grims(launch({ env: { RISHOT_CAPTURE: "screencopy" } })).length === 0,
    "RISHOT_CAPTURE=screencopy skips the pre-capture");
check(frozenOf(launch({ env: { RISHOT_CAPTURE: "screencopy" } })) === "",
    "RISHOT_CAPTURE=screencopy hands qs no PNG");
check(grims(launch({ env: { RISHOT_CAPTURE: "image" } })).length === 1,
    "RISHOT_CAPTURE=image still pre-captures");

for (const [name, opts] of [
    ["grim failing", { env: { STUB_GRAB: "fail" } }],
    ["grim writing an empty file", { env: { STUB_GRAB: "empty" } }],
    ["grim writing a non-PNG", { env: { STUB_GRAB: "junk" } }],
    ["grim missing", { have: ["qs"] }]
]) {
    const r = launch(opts);
    check(r.status === 0 && frozenOf(r) === "" && / width=$/.test(qsLine(r)), name + " falls back: qs starts with no PNG or width");
    check(r.left.length === 0, name + " leaves no scratch files");
}

// KDE goes through spectacle, the tool grabProc prefers there, and never grim.
for (const env of [{ XDG_CURRENT_DESKTOP: "KDE" }, { KDE_SESSION_VERSION: "6" }, { DESKTOP_SESSION: "plasmawayland" }]) {
    const r = launch({ env, have: ["qs", "grim", "spectacle"] });
    const spec = r.lines.find((l) => l.startsWith("spectacle ")) || "";
    check(spec === "spectacle -bnf -o " + frozenOf(r) && frozenOf(r) !== "",
        "KDE " + JSON.stringify(env) + " pre-captures with spectacle -bnf");
    check(grims(r).length === 0, "KDE " + JSON.stringify(env) + " does not try grim");
}
check(frozenOf(launch({ env: { XDG_CURRENT_DESKTOP: "KDE" } })) === "",
    "KDE without spectacle falls back to the overlay's own grab");

// Direct output reuses the same scratch dir and the single pre-capture.
{
    const r = launch({ args: ["--raw"] });
    check(r.status === 0 && r.stdout === "PNGDATA", "--raw still writes only the PNG to stdout");
    check(grims(r).length === 1, "--raw pre-captures exactly once");
    const m = /^qs frozen=(\S+) outfile=(\S+) width=/.exec(qsLine(r));
    check(m !== null && dirname(m[1]) === dirname(m[2]), "--raw hands qs the PNG and outfile in one scratch dir");
    check(r.left.length === 0, "--raw cleans its scratch dir");
}
{
    const r = launch({ args: ["--raw"], env: { STUB_GRAB: "fail" } });
    check(r.status === 0 && r.stdout === "PNGDATA", "--raw still works when the pre-capture fails");
}

// Cleanup survives a failing qs and a signal sent to the launcher.
{
    const r = launch({ env: { STUB_QS: "fail" } });
    check(r.status === 3, "qs failure status is passed through (" + r.status + ")");
    check(r.left.length === 0, "scratch dir is removed when qs fails");
}
// The stub qs signals the launcher, then would linger 5s: the launcher must stop it.
for (const args of [[], ["--raw"]]) {
    const name = args.length ? args.join(" ") : "editor mode";
    const t0 = Date.now();
    const r = launch({ args, env: { STUB_QS: "term" } });
    const ms = Date.now() - t0;
    check(r.status === 143, name + ": SIGTERM to the launcher exits 143 (" + r.status + ")");
    check(!r.lines.includes("qs survived") && ms < 3000,
        name + ": SIGTERM to the launcher is forwarded to qs (" + ms + " ms)");
    check(r.left.length === 0, name + ": scratch dir is removed after SIGTERM");
}

// A second press while one instance holds the lock must not grab the screen.
{
    const r = launch({ wrap: 'exec 8>"$XDG_RUNTIME_DIR/rishot.lock"; flock -n 8 || exit 99; "$@"' });
    check(r.status === 0 && r.lines.length === 0, "already running: no grab and no qs");
}

console.log(failed === 0 ? "\nAll tests PASSED" : "\n" + failed + " test(s) FAILED");
process.exit(failed === 0 ? 0 : 1);
