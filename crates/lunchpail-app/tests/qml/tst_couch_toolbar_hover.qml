import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchToolbarHover"
    when: windowShown
    visible: true
    width: 960; height: 540

    Component {
        id: sceneComponent
        Item {
            id: scene
            width: 960; height: 540
            property alias sensor: sensor
            property alias button: button
            property alias category: category
            property int clicks: 0
            property bool browseOnly: !sensor.hovered
            Rectangle { anchors.fill: parent; color: "#cc7733" }
            Rectangle { anchors.fill: parent; visible: !scene.browseOnly; color: "#aa101820" }
            Lunchpail.CouchToolbarHoverArea { id: sensor }
            Lunchpail.CouchActionButton {
                id: button
                x: 610; y: 32; z: 31
                visible: !scene.browseOnly
                text: "Library & settings"
                onClicked: scene.clicks++
            }
            Rectangle {
                id: category
                x: 300; y: 95; width: 110; height: 36
                visible: !scene.browseOnly
                color: categoryHover.hovered ? "orange" : "white"
                property alias hovered: categoryHover.hovered
                HoverHandler { id: categoryHover }
                TapHandler { onTapped: scene.clicks++ }
            }
        }
    }
    SignalSpy { id: transitions; signalName: "browseOnlyChanged" }

    function init() { mouseMove(test, 10, 520) }
    function cleanup() { transitions.target = null; mouseMove(test, 10, 520) }
    function test_hidden_or_disabled_sensor_cannot_reveal_controls() {
        const scene = createTemporaryObject(sceneComponent, test)
        mouseMove(scene, 580, 52)
        tryCompare(scene, "browseOnly", false)
        scene.sensor.enabled = false
        compare(scene.browseOnly, true)
        scene.sensor.enabled = true
        mouseMove(scene, 581, 52)
        tryCompare(scene, "browseOnly", false)
        scene.sensor.visible = false
        compare(scene.browseOnly, true)
    }
    function test_controls_do_not_interrupt_reveal_data() {
        return [{tag: "game-toolbar", platform: false, scale: 1},
                {tag: "platform-toolbar", platform: true, scale: 1},
                {tag: "scaled-game-toolbar", platform: false, scale: 0.67}]
    }
    function test_controls_do_not_interrupt_reveal(data) {
        const scene = createTemporaryObject(sceneComponent, test)
        verify(scene)
        scene.scale = data.scale
        scene.transformOrigin = Item.TopLeft
        if (data.platform) { scene.sensor.z = 3; scene.button.z = 2 }
        verify(scene.browseOnly)
        mouseMove(scene, 580, 52)
        tryCompare(scene, "browseOnly", false)
        transitions.target = scene; transitions.clear()
        for (let i = 0; i < 24; ++i) {
            mouseMove(scene.button, 12 + i * 3, scene.button.height / 2, 16)
            verify(!scene.browseOnly, "Hovering a revealed button must not hide its own toolbar")
            verify(scene.button.hovered, "Reveal sensor must not block button hover")
        }
        wait(600)
        compare(transitions.count, 0, "A stationary pointer must not toggle the full-screen scrim")
        verify(scene.button.hovered)
        mouseClick(scene.button)
        compare(scene.clicks, 1, "Reveal sensor must let clicks through")
        mouseMove(scene.category, 40, 18)
        tryCompare(scene.category, "hovered", true)
        mouseClick(scene.category, 40, 18)
        compare(scene.clicks, 2)
        compare(transitions.count, 0)
        mouseMove(scene, 500, 300)
        tryCompare(scene, "browseOnly", true)
        compare(transitions.count, 1, "Only leaving the reveal band should hide the controls")
    }
}
