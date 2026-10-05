import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchActionButton"
    when: windowShown
    visible: true
    width: 320; height: 100

    Component {
        id: buttonComponent
        Lunchpail.CouchActionButton {
            property bool muted: true
            text: muted ? "Unmute all game videos" : "Mute all game videos"
            iconName: muted ? "mute" : "volume"
            onClicked: muted = !muted
        }
    }
    QtObject {
        id: sounds
        property var heard: []
        function play(kind) { heard = heard.concat(kind); return true }
    }
    function test_pointer_and_keyboard_actions_emit_the_button_cue() {
        const button = createTemporaryObject(buttonComponent, test,
                                             {x: 20, y: 20, soundFeedback: sounds})
        sounds.heard = []
        mouseClick(button)
        compare(sounds.heard.filter(kind => kind === "confirm").length, 1)
        button.soundCue = "back"
        button.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(sounds.heard.filter(kind => kind === "back").length, 1)
        button.soundCue = ""
        sounds.heard = []
        keyClick(Qt.Key_Space)
        compare(sounds.heard.length, 0, "Actions with their own feedback must not double-play")
        mouseMove(test, 300, 90)
    }

    function test_icon_click_and_keyboard_keep_accessible_action() {
        const button = createTemporaryObject(buttonComponent, test, {x: 20, y: 20})
        verify(button)
        const icon = findChild(button, "couchActionIcon")
        const label = findChild(button, "couchActionLabel")
        compare(button.width, 44)
        compare(button.height, 44)
        verify(icon.visible)
        verify(!label.visible)
        compare(icon.name, "mute")
        compare(button.Accessible.name, "Unmute all game videos")
        mouseClick(button)
        verify(!button.muted)
        compare(icon.name, "volume")
        compare(button.Accessible.name, "Mute all game videos")
        button.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(button.muted)
        compare(icon.name, "mute")
        const center = icon.mapToItem(button, icon.width / 2, icon.height / 2)
        fuzzyCompare(center.x, button.width / 2, 0.1)
        fuzzyCompare(center.y, button.height / 2, 0.1)
    }

    function test_text_buttons_have_no_decorative_overline() {
        const button = createTemporaryObject(buttonComponent, test,
                                             {text: "Pause video", iconName: ""})
        verify(button)
        verify(!findChild(button, "couchActionIcon").visible)
        verify(findChild(button, "couchActionLabel").visible)
        verify(button.width > 44)
        compare(button.background.children.length, 0)
    }
}
