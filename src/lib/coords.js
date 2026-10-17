function intersectRect(globalRect, screenRect) {
    var gx1 = globalRect.x;
    var gy1 = globalRect.y;
    var gx2 = globalRect.x + globalRect.w;
    var gy2 = globalRect.y + globalRect.h;

    var sx1 = screenRect.x;
    var sy1 = screenRect.y;
    var sx2 = screenRect.x + screenRect.width;
    var sy2 = screenRect.y + screenRect.height;

    var ix1 = Math.max(gx1, sx1);
    var iy1 = Math.max(gy1, sy1);
    var ix2 = Math.min(gx2, sx2);
    var iy2 = Math.min(gy2, sy2);

    if (ix2 <= ix1 || iy2 <= iy1) return null;

    return {
        x: ix1 - screenRect.x,
        y: iy1 - screenRect.y,
        w: ix2 - ix1,
        h: iy2 - iy1
    };
}

function rectFromPoints(a, b) {
    var x = Math.min(a.x, b.x);
    var y = Math.min(a.y, b.y);
    return { x: x, y: y, w: Math.abs(b.x - a.x), h: Math.abs(b.y - a.y) };
}

/** The pointer stops one pixel short of a monitor's right and bottom edge; snap it onto the edge. */
function snapEdge(p, screens) {
    for (var i = 0; i < screens.length; i++) {
        var s = screens[i];
        if (p.x < s.x || p.x >= s.x + s.width || p.y < s.y || p.y >= s.y + s.height) continue;
        return {
            x: p.x >= s.x + s.width - 1 ? s.x + s.width : p.x,
            y: p.y >= s.y + s.height - 1 ? s.y + s.height : p.y
        };
    }
    return p;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { intersectRect, rectFromPoints, snapEdge };
}
