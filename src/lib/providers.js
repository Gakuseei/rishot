/**
 * Window enumeration providers for region-mode window-snap.
 *
 * Each parser turns a compositor's CLI query output into an array of window
 * rectangles in GLOBAL compositor coordinates:
 *   [{ x, y, w, h, z }]
 * A smaller z means the window is visually closer to the top, matching the
 * caller's hit test which prefers the rect with the lowest z under the cursor.
 *
 * Full-screen, region and monitor selection are compositor-agnostic and do not
 * rely on these parsers; any parser may return [] to degrade gracefully without
 * affecting those paths.
 */

/**
 * Parse Hyprland monitor and client JSON into global window rects.
 *
 * Replicates the union of `hyprctl monitors -j` active-workspace collection and
 * `hyprctl clients -j` window filtering: a client is kept only when it is mapped
 * and not hidden, sits on an active workspace, and has a positive size.
 *
 * @param {string} monitorsJson Raw stdout of `hyprctl monitors -j`.
 * @param {string} clientsJson Raw stdout of `hyprctl clients -j`.
 * @returns {Array<{x: number, y: number, w: number, h: number, z: number}>}
 */
function parseHyprland(monitorsJson, clientsJson) {
    var rects = [];
    try {
        var activeWs = [];
        var monitors = JSON.parse(monitorsJson);
        for (var m = 0; m < monitors.length; m++) {
            if (monitors[m].activeWorkspace) activeWs.push(monitors[m].activeWorkspace.id);
        }
        var clients = JSON.parse(clientsJson);
        for (var i = 0; i < clients.length; i++) {
            var c = clients[i];
            if (!c.mapped || c.hidden) continue;
            if (!c.workspace || activeWs.indexOf(c.workspace.id) === -1) continue;
            if (!c.size || c.size[0] <= 0 || c.size[1] <= 0) continue;
            if (!c.at) continue;
            rects.push({ x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], z: c.focusHistoryID });
        }
    } catch (e) {
        return [];
    }
    return rects;
}

/**
 * Test whether a Sway tree node is a real application window.
 *
 * A window is a leaf (no tiled or floating children) carrying a positive `rect`
 * that represents an application: a Wayland `app_id`, a non-null X11 `window`,
 * or a `pid`. Explicitly invisible nodes are rejected when the `visible` field
 * is present.
 *
 * @param {object} node A node from the Sway tree.
 * @returns {boolean}
 */
function isSwayWindow(node) {
    var hasChildren = (node.nodes && node.nodes.length > 0)
        || (node.floating_nodes && node.floating_nodes.length > 0);
    if (hasChildren) return false;
    if (!node.rect || node.rect.width <= 0 || node.rect.height <= 0) return false;
    if (node.visible === false) return false;
    var isApp = (typeof node.app_id === "string" && node.app_id.length > 0)
        || (node.window !== undefined && node.window !== null)
        || (node.pid !== undefined && node.pid !== null);
    return isApp;
}

/**
 * Parse `swaymsg -t get_tree` output into global window rects.
 *
 * Sway `rect` is already in absolute global layout coordinates (output offsets
 * included), so it maps directly. Windows discovered later in the recursion
 * (deeper containers and floating nodes, drawn on top) receive smaller z values
 * so the topmost window wins the caller's hit test.
 *
 * @param {string} treeJson Raw stdout of `swaymsg -t get_tree`.
 * @returns {Array<{x: number, y: number, w: number, h: number, z: number}>}
 */
function parseSway(treeJson) {
    var found = [];
    try {
        var tree = JSON.parse(treeJson);
        var walk = function (node) {
            if (!node) return;
            var children = (node.nodes || []).concat(node.floating_nodes || []);
            for (var i = 0; i < children.length; i++) walk(children[i]);
            if (isSwayWindow(node)) {
                found.push({ x: node.rect.x, y: node.rect.y, w: node.rect.width, h: node.rect.height });
            }
        };
        walk(tree);
    } catch (e) {
        return [];
    }
    var n = found.length;
    var rects = [];
    for (var k = 0; k < n; k++) {
        rects.push({ x: found[k].x, y: found[k].y, w: found[k].w, h: found[k].h, z: n - 1 - k });
    }
    return rects;
}

/**
 * Build a workspace-id to output-name map from `niri msg --json workspaces`.
 *
 * Niri windows reference a `workspace_id` rather than an output directly, so the
 * workspace list is the bridge to the owning output.
 *
 * @param {Array} workspaces Parsed workspaces payload (array of `{id, output}`).
 * @returns {Object<string, string>}
 */
function niriWorkspaceMap(workspaces) {
    var map = {};
    if (Array.isArray(workspaces)) {
        for (var i = 0; i < workspaces.length; i++) {
            var ws = workspaces[i];
            if (ws && ws.id !== undefined && ws.id !== null && ws.output)
                map[ws.id] = ws.output;
        }
    }
    return map;
}

/**
 * Build an output-name to logical-geometry map from `niri msg --json outputs`.
 *
 * Handles both shapes niri exposes across versions: an object keyed by output
 * name (the current `HashMap<String, Output>` form) and an array of output
 * objects each carrying a `name`. Outputs without a `logical` block (disabled)
 * are skipped.
 *
 * @param {object|Array} outputs Parsed outputs payload.
 * @returns {Object<string, {x: number, y: number, width: number, height: number, scale: number}>}
 */
function niriOutputMap(outputs) {
    var map = {};
    if (Array.isArray(outputs)) {
        for (var i = 0; i < outputs.length; i++) {
            var o = outputs[i];
            if (o && o.name && o.logical) map[o.name] = o.logical;
        }
    } else if (outputs && typeof outputs === "object") {
        for (var name in outputs) {
            if (!Object.prototype.hasOwnProperty.call(outputs, name)) continue;
            var entry = outputs[name];
            if (entry && entry.logical) map[name] = entry.logical;
        }
    }
    return map;
}

/**
 * Parse niri windows, workspaces and outputs into global window rects.
 *
 * A niri window carries no output; its global position is reconstructed by
 * joining `window.workspace_id` to the owning workspace's `output`, then to that
 * output's `logical` origin. The tiled position `layout.tile_pos_in_workspace_view`
 * is expressed relative to the output's logical view, so the logical origin is
 * added to produce global coordinates. Windows without a tile position (floating
 * or not currently laid out), on an unknown workspace, or on an unknown/disabled
 * output are skipped. The focused window receives the smallest z; all others are
 * ordered by a counter.
 *
 * @param {string} windowsJson Raw stdout of `niri msg --json windows`.
 * @param {string} workspacesJson Raw stdout of `niri msg --json workspaces`.
 * @param {string} outputsJson Raw stdout of `niri msg --json outputs`.
 * @returns {Array<{x: number, y: number, w: number, h: number, z: number}>}
 */
function parseNiri(windowsJson, workspacesJson, outputsJson) {
    var rects = [];
    try {
        var windows = JSON.parse(windowsJson);
        var workspaceMap = niriWorkspaceMap(JSON.parse(workspacesJson));
        var outputMap = niriOutputMap(JSON.parse(outputsJson));
        var counter = 1;
        for (var i = 0; i < windows.length; i++) {
            var win = windows[i];
            var layout = win.layout;
            if (!layout) continue;
            var tilePos = layout.tile_pos_in_workspace_view;
            if (!tilePos) continue;
            var size = layout.window_size;
            if (!size || size[0] <= 0 || size[1] <= 0) continue;
            var outName = workspaceMap[win.workspace_id];
            if (!outName) continue;
            var out = outputMap[outName];
            if (!out) continue;
            rects.push({
                x: out.x + tilePos[0],
                y: out.y + tilePos[1],
                w: size[0],
                h: size[1],
                z: win.is_focused ? 0 : counter++
            });
        }
    } catch (e) {
        return [];
    }
    return rects;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { parseHyprland, parseSway, parseNiri };
}
