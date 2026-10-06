import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "CouchSharedTools"
    when: windowShown
    Component {
        id: appComponent
        ApplicationWindow {
            id: app
            width: 600; height: 400
            visible: true
            property alias router: navigation
            property alias dialog: toolsDialog
            property alias button: dialogButton
            property alias nested: nestedDialog
            QtObject {
                // Model-like objects coexist with visual children in Main.
                function data() { return null }
            }
            QtObject {
                id: gamepad
                property int navigation_revision: 0
                property string navigation_action: ""
                property string active_device: ""
                property int connected_count: 1
            }
            Lunchpail.DesktopGamepadNavigation {
                id: navigation
                applicationWindow: app
                gamepad: gamepad
                overlayItem: Overlay.overlay
            }
            // A menu button has contentItem + close(), but is not a popup.
            // It must not intercept Back when its menu is closed.
            Lunchpail.LibraryMenu { text: "Library" }
            Lunchpail.LbDialog {
                id: toolsDialog
                parent: Overlay.overlay
                width: 400; height: 250
                modal: true
                title: "Couch tools"
                contentItem: Lunchpail.LbButton { id: dialogButton; text: "Settings" }
            }
            Lunchpail.LbDialog {
                id: nestedDialog
                parent: Overlay.overlay
                width: 200; height: 150; modal: true
                title: "Nested editor"
            }
        }
    }
    function test_shared_dialog_has_focus_scope_and_controller_back() {
        const app = createTemporaryObject(appComponent, this)
        verify(app)
        app.dialog.open()
        tryVerify(function() { return app.router.popupScope !== null })
        verify(app.router.within(app.button, app.router.currentScope()))
        verify(app.router.closeFocusedPopup())
        tryCompare(app.dialog, "visible", false)
    }
    function test_closed_menu_button_is_not_an_open_popup() {
        const app = createTemporaryObject(appComponent, this)
        verify(!app.router.closeFocusedPopup())
    }
    function test_escape_closes_dialog_without_custom_focus_handler() {
        const app = createTemporaryObject(appComponent, this)
        app.dialog.open()
        tryVerify(function() { return app.router.popupScope !== null })
        keyClick(Qt.Key_Escape)
        tryCompare(app.dialog, "visible", false)
    }
    function test_nested_close_restores_parent_dialog_before_browsing() {
        const app = createTemporaryObject(appComponent, this)
        app.dialog.open()
        tryVerify(function() { return app.router.popupScope !== null })
        app.nested.open()
        tryCompare(app.nested, "opened", true)
        keyClick(Qt.Key_Escape)
        tryCompare(app.nested, "visible", false)
        verify(app.dialog.visible)
        // Match the brief focus gap during a full-window editor's teardown.
        app.contentItem.forceActiveFocus()
        verify(app.router.focusOpenPopup())
        tryVerify(function() { return app.router.within(app.button, app.router.popupScope) })
        keyClick(Qt.Key_Escape)
        tryCompare(app.dialog, "visible", false)
        verify(!app.router.focusOpenPopup())
    }
    function test_back_finds_unfocused_dialog_and_respects_protected_workflows() {
        const app = createTemporaryObject(appComponent, this)
        app.dialog.open()
        tryCompare(app.dialog, "visible", true)
        app.contentItem.forceActiveFocus()
        verify(app.router.closeFocusedPopup())
        tryCompare(app.dialog, "visible", false)
        app.dialog.closePolicy = Popup.NoAutoClose
        app.dialog.open()
        tryCompare(app.dialog, "visible", true)
        verify(app.router.closeFocusedPopup())
        verify(app.dialog.visible)
    }
    Component {
        id: scaledControl
        Item {
            x: 20; y: 30; width: 100; height: 50
            scale: 2
            transformOrigin: Item.TopLeft
        }
    }
    function test_scaled_couch_controls_use_window_coordinates() {
        const app = createTemporaryObject(appComponent, this)
        const item = createTemporaryObject(scaledControl, app.contentItem)
        const rect = app.router.visibleRect(item)
        verify(rect)
        compare(rect.right - rect.x, 200)
        compare(rect.bottom - rect.y, 100)
    }
}
