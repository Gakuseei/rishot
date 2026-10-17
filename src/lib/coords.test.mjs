import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { intersectRect, rectFromPoints, snapEdge } = require("./coords.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) {
        console.log("PASS " + msg);
    } else {
        failed++;
        console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a);
    }
}

const span = { x: 2400, y: 200, w: 400, h: 300 };
const hdmi = { x: 0, y: 0, width: 2560, height: 1440 };
const dp = { x: 2560, y: 0, width: 2560, height: 1440 };

eq(intersectRect(span, hdmi), { x: 2400, y: 200, w: 160, h: 300 }, "intersect span on HDMI-A-1");
eq(intersectRect(span, dp), { x: 0, y: 200, w: 240, h: 300 }, "intersect span on DP-1");

const onDp = { x: 2700, y: 300, w: 700, h: 450 };
eq(intersectRect(onDp, hdmi), null, "DP-only selection has no HDMI intersection");
eq(intersectRect(onDp, dp), { x: 140, y: 300, w: 700, h: 450 }, "DP-only selection local on DP-1");

eq(rectFromPoints({ x: 100, y: 100 }, { x: 40, y: 30 }), { x: 40, y: 30, w: 60, h: 70 }, "rectFromPoints normalizes");

const screens = [hdmi, dp];
eq(snapEdge({ x: 5119, y: 1439 }, screens), { x: 5120, y: 1440 }, "snapEdge reaches bottom-right corner");
eq(snapEdge({ x: 2559, y: 700 }, screens), { x: 2560, y: 700 }, "snapEdge reaches HDMI right edge");
eq(snapEdge({ x: 2560, y: 700 }, screens), { x: 2560, y: 700 }, "snapEdge leaves DP left edge alone");
eq(snapEdge({ x: 1200, y: 600 }, screens), { x: 1200, y: 600 }, "snapEdge leaves interior points alone");

if (failed > 0) {
    console.log("\n" + failed + " test(s) FAILED");
    process.exit(1);
}
console.log("\nAll tests PASSED");
