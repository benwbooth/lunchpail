import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as Lunchpail

Item {
    ApplicationWindow {
        id: window
        visible: true; width: 900; height: 700
        TestCase {
            id: test
            name: "HandsFreeInputGuard"
            when: windowShown
            property bool showTip: false
            Item {
                id: conversation
                parent: Overlay.overlay
                width: 400; height: 300
            }
            Lunchpail.HandsFreeInputGuard {
                id: guard
                overlayItem: Overlay.overlay
                ignoredItem: conversation
            }
            Button {
                text: "Hands-free"
                ToolTip.visible: test.showTip
                ToolTip.text: "Turn hands-free listening off · F4"
            }
            Dialog { id: settings; parent: Overlay.overlay; modal: true; width: 400; height: 300 }
            Menu { id: menu; MenuItem { text: "A menu action" } }
            function cleanup() { showTip = false; settings.close(); menu.close(); wait(300) }
            function test_tooltip_never_blocks_listening() {
                compare(guard.blocked, false)
                showTip = true
                tryVerify(() => guard.tooltipItem && guard.tooltipItem.visible)
                compare(guard.blocked, false)
                showTip = false
                tryVerify(() => !guard.tooltipItem.visible)
                compare(guard.blocked, false)
            }
            function test_modal_dialog_blocks_even_without_keyboard_focus() {
                settings.open(); tryCompare(guard, "blocked", true)
                conversation.forceActiveFocus(); compare(guard.blocked, true)
                settings.close(); tryCompare(guard, "blocked", false)
            }
            function test_menu_blocks_and_tooltip_does_not_hide_it() {
                menu.open(); tryCompare(guard, "blocked", true)
                showTip = true; wait(100); compare(guard.blocked, true)
                menu.close(); tryCompare(guard, "blocked", false)
            }
        }
    }
}
