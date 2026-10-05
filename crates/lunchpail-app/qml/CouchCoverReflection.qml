import QtQuick
import QtQuick.Effects

// A shallow, fading floor reflection. Only the visible cover-flow delegates
// allocate textures; it never samples the video or the whole browser.
Item {
    id: reflection
    required property Item sourceItem
    opacity: 0.25
    Item {
        id: mirrored
        anchors.fill: parent
        visible: false
        layer.enabled: reflection.visible
        ShaderEffectSource {
            width: reflection.width; height: reflection.height
            sourceItem: reflection.visible ? reflection.sourceItem : null
            sourceRect: Qt.rect(0, Math.max(0, reflection.sourceItem.height - height),
                                reflection.sourceItem.width, height)
            live: reflection.visible
            transform: Scale { origin.y: reflection.height / 2; yScale: -1 }
        }
    }
    Rectangle {
        id: fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: reflection.visible
        gradient: Gradient {
            GradientStop { position: 0; color: "white" }
            GradientStop { position: 0.85; color: "transparent" }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: mirrored
        maskEnabled: true
        maskSource: fadeMask
        autoPaddingEnabled: false
    }
}
