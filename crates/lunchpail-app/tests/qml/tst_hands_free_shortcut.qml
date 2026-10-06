import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "HandsFreeShortcut"
    when: windowShown
    visible: true; width: 640; height: 480
    property bool handsFreeEnabled: false
    QtObject {
        id: desktop
        property int toggles: 0
        function toggleHandsFree() { toggles++; test.handsFreeEnabled = !test.handsFreeEnabled }
    }
    QtObject {
        id: couch
        property int toggles: 0
        function toggleHandsFree() { toggles++; test.handsFreeEnabled = !test.handsFreeEnabled }
    }
    QtObject {
        id: setup
        property bool pending: false
        property int cancels: 0
        function cancel() { pending = false; cancels++ }
    }
    Lunchpail.HandsFreeShortcut {
        id: shortcut
        desktopController: desktop; couchController: couch
        setupControllers: [setup]
    }
    TextField { id: field; width: 300; placeholderText: "Conversation" }
    Popup {
        id: dialog
        modal: true; width: 300; height: 100
        contentItem: TextField { id: dialogField }
    }
    function init() {
        handsFreeEnabled = false
        desktop.toggles = 0; couch.toggles = 0
        shortcut.couchModeActive = false
        setup.pending = false; setup.cancels = 0
        field.forceActiveFocus()
    }
    function cleanup() { dialog.close() }
    function test_f4_toggles_normal_mode_both_ways_without_consuming_typing() {
        keyClick(Qt.Key_F4)
        compare(handsFreeEnabled, true); compare(desktop.toggles, 1); compare(couch.toggles, 0)
        keyClick(Qt.Key_F4)
        compare(handsFreeEnabled, false); compare(desktop.toggles, 2)
        keyClick(Qt.Key_H); compare(field.text, "h")
        field.clear()
        compare(shortcut.autoRepeat, false)
        compare(shortcut.context, Qt.ApplicationShortcut)
    }
    function test_f4_uses_the_same_preference_after_switching_to_couch_mode() {
        keyClick(Qt.Key_F4); compare(handsFreeEnabled, true)
        shortcut.couchModeActive = true
        keyClick(Qt.Key_F4)
        compare(handsFreeEnabled, false); compare(couch.toggles, 1); compare(desktop.toggles, 1)
        keyClick(Qt.Key_F4); compare(handsFreeEnabled, true); compare(couch.toggles, 2)
    }
    function test_f4_remains_available_in_a_modal_settings_or_install_dialog() {
        dialog.open(); tryCompare(dialog, "opened", true)
        dialogField.forceActiveFocus()
        keyClick(Qt.Key_F4)
        compare(handsFreeEnabled, true); compare(desktop.toggles, 1)
        keyClick(Qt.Key_F4); compare(handsFreeEnabled, false)
    }
    function test_f2_does_not_toggle_hands_free() {
        keyClick(Qt.Key_F2)
        compare(handsFreeEnabled, false); compare(desktop.toggles, 0); compare(couch.toggles, 0)
    }
    function test_f4_cancels_setup_started_from_settings_without_a_second_flow() {
        dialog.open(); tryCompare(dialog, "opened", true)
        setup.pending = true; dialogField.forceActiveFocus()
        keyClick(Qt.Key_F4)
        compare(setup.pending, false); compare(setup.cancels, 1)
        compare(desktop.toggles, 0); compare(couch.toggles, 0)
        compare(handsFreeEnabled, false)
    }
}
