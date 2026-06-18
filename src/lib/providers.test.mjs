import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { parseHyprland, parseSway, parseNiri } = require("./providers.js");

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

const hyprMonitors = JSON.stringify([
    { id: 0, name: "DP-1", activeWorkspace: { id: 1, name: "1" } },
    { id: 1, name: "HDMI-A-1", activeWorkspace: { id: 5, name: "5" } }
]);
const hyprClients = JSON.stringify([
    { mapped: true, hidden: false, workspace: { id: 1 }, at: [10, 20], size: [800, 600], focusHistoryID: 0 },
    { mapped: true, hidden: false, workspace: { id: 5 }, at: [2560, 0], size: [1280, 720], focusHistoryID: 1 },
    { mapped: true, hidden: false, workspace: { id: 9 }, at: [40, 40], size: [400, 300], focusHistoryID: 2 },
    { mapped: false, hidden: false, workspace: { id: 1 }, at: [0, 0], size: [500, 500], focusHistoryID: 3 },
    { mapped: true, hidden: true, workspace: { id: 1 }, at: [0, 0], size: [500, 500], focusHistoryID: 4 },
    { mapped: true, hidden: false, workspace: { id: 1 }, at: [0, 0], size: [0, 0], focusHistoryID: 5 }
]);
eq(parseHyprland(hyprMonitors, hyprClients), [
    { x: 10, y: 20, w: 800, h: 600, z: 0 },
    { x: 2560, y: 0, w: 1280, h: 720, z: 1 }
], "hyprland keeps active-workspace mapped windows only");
eq(parseHyprland("not json", hyprClients), [], "hyprland bad monitors json -> []");
eq(parseHyprland(hyprMonitors, "}{"), [], "hyprland bad clients json -> []");

const hyprClientsMissingAt = JSON.stringify([
    { mapped: true, hidden: false, workspace: { id: 1 }, size: [500, 500], focusHistoryID: 0 },
    { mapped: true, hidden: false, workspace: { id: 1 }, at: [10, 20], size: [800, 600], focusHistoryID: 1 }
]);
eq(parseHyprland(hyprMonitors, hyprClientsMissingAt), [
    { x: 10, y: 20, w: 800, h: 600, z: 1 }
], "hyprland client missing 'at' is skipped, not fatal to the whole parse");

const swayTree = JSON.stringify({
    type: "root",
    rect: { x: 0, y: 0, width: 3840, height: 1080 },
    nodes: [
        {
            type: "output",
            name: "DP-1",
            rect: { x: 0, y: 0, width: 2560, height: 1080 },
            nodes: [
                {
                    type: "workspace",
                    name: "1",
                    rect: { x: 0, y: 0, width: 2560, height: 1080 },
                    nodes: [
                        {
                            type: "con",
                            app_id: "foot",
                            pid: 111,
                            visible: true,
                            rect: { x: 0, y: 0, width: 1280, height: 1080 },
                            nodes: [],
                            floating_nodes: []
                        },
                        {
                            type: "con",
                            rect: { x: 1280, y: 0, width: 1280, height: 1080 },
                            nodes: [
                                {
                                    type: "con",
                                    app_id: "firefox",
                                    pid: 222,
                                    visible: true,
                                    rect: { x: 1280, y: 0, width: 1280, height: 1080 },
                                    nodes: [],
                                    floating_nodes: []
                                }
                            ],
                            floating_nodes: []
                        }
                    ],
                    floating_nodes: [
                        {
                            type: "floating_con",
                            app_id: null,
                            window: 4194305,
                            pid: 333,
                            visible: true,
                            rect: { x: 600, y: 300, width: 640, height: 480 },
                            nodes: [],
                            floating_nodes: []
                        }
                    ]
                }
            ],
            floating_nodes: []
        }
    ],
    floating_nodes: []
});
eq(parseSway(swayTree), [
    { x: 0, y: 0, w: 1280, h: 1080, z: 2 },
    { x: 1280, y: 0, w: 1280, h: 1080, z: 1 },
    { x: 600, y: 300, w: 640, h: 480, z: 0 }
], "sway extracts 2 tiled + 1 floating, container excluded, floating gets top z");
eq(parseSway("nope"), [], "sway bad json -> []");

const niriWindows = JSON.stringify([
    {
        id: 1, workspace_id: 1, is_focused: false,
        layout: { tile_pos_in_workspace_view: [10, 20], window_size: [800, 600] }
    },
    {
        id: 2, workspace_id: 3, is_focused: true,
        layout: { tile_pos_in_workspace_view: [5, 5], window_size: [1280, 720] }
    },
    {
        id: 3, workspace_id: 1, is_focused: false,
        layout: { tile_pos_in_workspace_view: null, window_size: [300, 300] }
    },
    {
        id: 4, workspace_id: 99, is_focused: false,
        layout: { tile_pos_in_workspace_view: [1, 1], window_size: [200, 200] }
    }
]);
const niriWorkspaces = JSON.stringify([
    { id: 1, output: "DP-1", is_active: true, is_focused: false },
    { id: 2, output: "DP-1", is_active: false, is_focused: false },
    { id: 3, output: "HDMI-A-1", is_active: true, is_focused: true }
]);
const niriOutputsObject = JSON.stringify({
    "DP-1": { name: "DP-1", logical: { x: 0, y: 0, width: 2560, height: 1440, scale: 1 } },
    "HDMI-A-1": { name: "HDMI-A-1", logical: { x: 2560, y: 0, width: 1920, height: 1080, scale: 1 } }
});
const niriOutputsArray = JSON.stringify([
    { name: "DP-1", logical: { x: 0, y: 0, width: 2560, height: 1440, scale: 1 } },
    { name: "HDMI-A-1", logical: { x: 2560, y: 0, width: 1920, height: 1080, scale: 1 } }
]);
const niriExpected = [
    { x: 10, y: 20, w: 800, h: 600, z: 1 },
    { x: 2565, y: 5, w: 1280, h: 720, z: 0 }
];
eq(parseNiri(niriWindows, niriWorkspaces, niriOutputsObject), niriExpected, "niri object outputs: workspace->output join, logical offset, focused z=0, null tile + unknown workspace excluded");
eq(parseNiri(niriWindows, niriWorkspaces, niriOutputsArray), niriExpected, "niri array outputs: same result as object shape");
const niriOutputsDisabled = JSON.stringify({
    "DP-1": { name: "DP-1", logical: null },
    "HDMI-A-1": { name: "HDMI-A-1", logical: { x: 2560, y: 0, width: 1920, height: 1080, scale: 1 } }
});
eq(parseNiri(niriWindows, niriWorkspaces, niriOutputsDisabled), [
    { x: 2565, y: 5, w: 1280, h: 720, z: 0 }
], "niri disabled output (logical:null) drops its window, keeps the other");

eq(parseNiri(niriWindows, niriWorkspaces, "{bad"), [], "niri bad outputs json -> []");
eq(parseNiri(niriWindows, "{bad", niriOutputsObject), [], "niri bad workspaces json -> []");
eq(parseNiri("{bad", niriWorkspaces, niriOutputsObject), [], "niri bad windows json -> []");

if (failed > 0) {
    console.log("\n" + failed + " test(s) FAILED");
    process.exit(1);
}
console.log("\nAll tests PASSED");
