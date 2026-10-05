import QtQuick

// A tightly packed logo arc with a magnifying focus region. Both game and
// system wheels use this path, including its depth ordering during motion.
Path {
    id: path
    property real viewportWidth: 640
    property real viewportHeight: 720
    startX: viewportWidth * 0.90
    startY: -viewportHeight * 0.13
    PathAttribute { name: "itemScale"; value: 0.44 }
    PathAttribute { name: "itemOpacity"; value: 0 }
    PathAttribute { name: "itemAngle"; value: -30 }
    PathAttribute { name: "itemDepth"; value: 0 }
    PathQuad { x: path.viewportWidth * 0.69; y: path.viewportHeight * 0.23
        controlX: path.viewportWidth * 0.84; controlY: path.viewportHeight * 0.08 }
    PathPercent { value: 0.25 }
    PathAttribute { name: "itemScale"; value: 0.58 }
    PathAttribute { name: "itemOpacity"; value: 0.70 }
    PathAttribute { name: "itemAngle"; value: -22 }
    PathAttribute { name: "itemDepth"; value: 2 }
    PathQuad { x: path.viewportWidth * 0.57; y: path.viewportHeight * 0.365
        controlX: path.viewportWidth * 0.62; controlY: path.viewportHeight * 0.30 }
    PathPercent { value: 0.40 }
    PathAttribute { name: "itemScale"; value: 0.72 }
    PathAttribute { name: "itemOpacity"; value: 0.94 }
    PathAttribute { name: "itemAngle"; value: -12 }
    PathAttribute { name: "itemDepth"; value: 6 }
    PathQuad { x: path.viewportWidth * 0.49; y: path.viewportHeight * 0.50
        controlX: path.viewportWidth * 0.49; controlY: path.viewportHeight * 0.43 }
    PathPercent { value: 0.50 }
    PathAttribute { name: "itemScale"; value: 1.18 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: 0 }
    PathAttribute { name: "itemDepth"; value: 30 }
    PathQuad { x: path.viewportWidth * 0.57; y: path.viewportHeight * 0.635
        controlX: path.viewportWidth * 0.49; controlY: path.viewportHeight * 0.57 }
    PathPercent { value: 0.60 }
    PathAttribute { name: "itemScale"; value: 0.72 }
    PathAttribute { name: "itemOpacity"; value: 0.94 }
    PathAttribute { name: "itemAngle"; value: 12 }
    PathAttribute { name: "itemDepth"; value: 6 }
    PathQuad { x: path.viewportWidth * 0.69; y: path.viewportHeight * 0.77
        controlX: path.viewportWidth * 0.62; controlY: path.viewportHeight * 0.70 }
    PathPercent { value: 0.75 }
    PathAttribute { name: "itemScale"; value: 0.58 }
    PathAttribute { name: "itemOpacity"; value: 0.70 }
    PathAttribute { name: "itemAngle"; value: 22 }
    PathAttribute { name: "itemDepth"; value: 2 }
    PathQuad { x: path.viewportWidth * 0.90; y: path.viewportHeight * 1.13
        controlX: path.viewportWidth * 0.84; controlY: path.viewportHeight * 0.92 }
    PathAttribute { name: "itemScale"; value: 0.44 }
    PathAttribute { name: "itemOpacity"; value: 0 }
    PathAttribute { name: "itemAngle"; value: 30 }
    PathAttribute { name: "itemDepth"; value: 0 }
}
