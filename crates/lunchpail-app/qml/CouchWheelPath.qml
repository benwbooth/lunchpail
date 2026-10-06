import QtQuick

// Classic right-hand HyperSpin arc. The offscreen hub is to the right:
// upper logos rotate clockwise, lower logos counterclockwise. Neighbor
// logos retain their color/opacity and are roughly 230/480 of focus size.
// PathView interpolates transforms; no per-frame JavaScript or raster layers.
Path {
    id: path
    property real viewportWidth: 640
    property real viewportHeight: 720
    startX: viewportWidth * 0.92
    startY: -viewportHeight * 0.08
    PathAttribute { name: "itemScale"; value: 0.48 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: 48 }
    PathAttribute { name: "itemDepth"; value: 0 }
    PathQuad { x: path.viewportWidth * 0.66; y: path.viewportHeight * 0.22
        controlX: path.viewportWidth * 0.76; controlY: path.viewportHeight * 0.07 }
    PathPercent { value: 0.25 }
    PathAttribute { name: "itemScale"; value: 0.48 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: 26 }
    PathAttribute { name: "itemDepth"; value: 2 }
    PathQuad { x: path.viewportWidth * 0.54; y: path.viewportHeight * 0.375
        controlX: path.viewportWidth * 0.58; controlY: path.viewportHeight * 0.30 }
    PathPercent { value: 0.40 }
    PathAttribute { name: "itemScale"; value: 0.52 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: 12 }
    PathAttribute { name: "itemDepth"; value: 6 }
    PathQuad { x: path.viewportWidth * 0.48; y: path.viewportHeight * 0.50
        controlX: path.viewportWidth * 0.48; controlY: path.viewportHeight * 0.43 }
    PathPercent { value: 0.50 }
    PathAttribute { name: "itemScale"; value: 1 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: 0 }
    PathAttribute { name: "itemDepth"; value: 30 }
    PathQuad { x: path.viewportWidth * 0.54; y: path.viewportHeight * 0.625
        controlX: path.viewportWidth * 0.48; controlY: path.viewportHeight * 0.57 }
    PathPercent { value: 0.60 }
    PathAttribute { name: "itemScale"; value: 0.52 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: -12 }
    PathAttribute { name: "itemDepth"; value: 6 }
    PathQuad { x: path.viewportWidth * 0.66; y: path.viewportHeight * 0.78
        controlX: path.viewportWidth * 0.58; controlY: path.viewportHeight * 0.70 }
    PathPercent { value: 0.75 }
    PathAttribute { name: "itemScale"; value: 0.48 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: -26 }
    PathAttribute { name: "itemDepth"; value: 2 }
    PathQuad { x: path.viewportWidth * 0.92; y: path.viewportHeight * 1.08
        controlX: path.viewportWidth * 0.76; controlY: path.viewportHeight * 0.93 }
    PathAttribute { name: "itemScale"; value: 0.48 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: -48 }
    PathAttribute { name: "itemDepth"; value: 0 }
}
