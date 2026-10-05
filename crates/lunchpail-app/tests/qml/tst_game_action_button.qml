import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "GameActionButton"
    when: windowShown
    visible: true
    width: 340; height: 180
    Component {
        id: actionComponent
        Lunchpail.GameActionButton {
            x: 30; y: 30
            text: "Play"
            iconName: "play"
            positive: true
        }
    }
    SignalSpy { id: clicks; signalName: "clicked" }

    function test_pointer_does_not_take_keyboard_focus() {
        const action = createTemporaryObject(actionComponent, test)
        clicks.target = action
        clicks.clear()
        mouseClick(action)
        compare(clicks.count, 1)
        verify(!action.activeFocus)
        action.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space)
        compare(clicks.count, 2)
        verify(action.visualFocus)
        compare(action.background.border.width, 2)
        clicks.target = null
    }

    function test_compact_icon_is_centered_and_keeps_accessible_name() {
        const action = createTemporaryObject(actionComponent, test, { showLabel: false })
        compare(action.width, 36)
        compare(action.Accessible.name, "Play")
        verify(!findChild(action, "gameActionLabel").visible)
        const icon = findChild(action, "gameActionIcon")
        verify(waitForRendering(action))
        const center = icon.mapToItem(action, icon.width / 2, icon.height / 2)
        fuzzyCompare(center.x, action.width / 2, 0.1)
        fuzzyCompare(center.y, action.height / 2, 0.1)
    }

    function test_busy_and_disabled_actions_cannot_launch() {
        const action = createTemporaryObject(actionComponent, test, { busy: true, enabled: false })
        clicks.target = action
        clicks.clear()
        verify(findChild(action, "gameActionProgress").visible)
        verify(!findChild(action, "gameActionIcon").visible)
        mouseClick(action)
        compare(clicks.count, 0)
        action.busy = false
        verify(!findChild(action, "gameActionProgress").visible)
        verify(findChild(action, "gameActionIcon").visible)
        mouseClick(action)
        compare(clicks.count, 0)
        action.enabled = true
        mouseClick(action)
        compare(clicks.count, 1)
        clicks.target = null
    }

    function test_labeled_action_groups_icon_and_text() {
        const action = createTemporaryObject(actionComponent, test)
        const label = findChild(action, "gameActionLabel")
        const icon = findChild(action, "gameActionIcon")
        verify(label.visible)
        compare(label.text, "Play")
        verify(waitForRendering(action))
        const left = icon.mapToItem(action, 0, 0).x
        const right = label.mapToItem(action, label.width, 0).x
        // Center anchors round to physical pixels while font metrics are fractional.
        fuzzyCompare(left, action.width - right, 1)
        verify(left >= 8)
    }

    function test_long_setup_label_stays_inside_narrow_button() {
        const action = createTemporaryObject(actionComponent, test, {
            width: 160, iconName: "", text: "Set up the selected emulator and firmware"
        })
        verify(waitForRendering(action))
        const label = findChild(action, "gameActionLabel")
        verify(label.truncated)
        verify(label.mapToItem(action, 0, 0).x >= action.leftPadding)
        verify(label.mapToItem(action, label.width, 0).x <= action.width - action.rightPadding)
    }
}
