import QtQuick

// Closely stacked covers turn out toward the viewer at the focus point.
Path {
    id: path
    property real viewportWidth: 1280
    property real viewportHeight: 480
    startX: -viewportWidth * 0.15; startY: viewportHeight * 0.51
    PathAttribute { name: "itemScale"; value: 0.62 }
    PathAttribute { name: "itemOpacity"; value: 0 }
    PathAttribute { name: "itemAngle"; value: 72 }
    PathAttribute { name: "itemDepth"; value: 0 }
    PathLine { x: path.viewportWidth * 0.28; y: path.viewportHeight * 0.51 }
    PathPercent { value: 0.30 }
    PathAttribute { name: "itemScale"; value: 0.76 }
    PathAttribute { name: "itemOpacity"; value: 0.76 }
    PathAttribute { name: "itemAngle"; value: 64 }
    PathAttribute { name: "itemDepth"; value: 3 }
    PathLine { x: path.viewportWidth * 0.39; y: path.viewportHeight * 0.49 }
    PathPercent { value: 0.42 }
    PathAttribute { name: "itemScale"; value: 0.84 }
    PathAttribute { name: "itemOpacity"; value: 0.96 }
    PathAttribute { name: "itemAngle"; value: 58 }
    PathAttribute { name: "itemDepth"; value: 8 }
    PathLine { x: path.viewportWidth * 0.50; y: path.viewportHeight * 0.44 }
    PathPercent { value: 0.50 }
    PathAttribute { name: "itemScale"; value: 1.12 }
    PathAttribute { name: "itemOpacity"; value: 1 }
    PathAttribute { name: "itemAngle"; value: 0 }
    PathAttribute { name: "itemDepth"; value: 30 }
    PathLine { x: path.viewportWidth * 0.61; y: path.viewportHeight * 0.49 }
    PathPercent { value: 0.58 }
    PathAttribute { name: "itemScale"; value: 0.84 }
    PathAttribute { name: "itemOpacity"; value: 0.96 }
    PathAttribute { name: "itemAngle"; value: -58 }
    PathAttribute { name: "itemDepth"; value: 8 }
    PathLine { x: path.viewportWidth * 0.72; y: path.viewportHeight * 0.51 }
    PathPercent { value: 0.70 }
    PathAttribute { name: "itemScale"; value: 0.76 }
    PathAttribute { name: "itemOpacity"; value: 0.76 }
    PathAttribute { name: "itemAngle"; value: -64 }
    PathAttribute { name: "itemDepth"; value: 3 }
    PathLine { x: path.viewportWidth * 1.15; y: path.viewportHeight * 0.51 }
    PathAttribute { name: "itemScale"; value: 0.62 }
    PathAttribute { name: "itemOpacity"; value: 0 }
    PathAttribute { name: "itemAngle"; value: -72 }
    PathAttribute { name: "itemDepth"; value: 0 }
}
