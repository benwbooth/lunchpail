import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "SettingsWindowHeader"
    visible: true; width: 1280; height: 300
    when: windowShown
    QtObject {
        id: app
        property int visibility: Window.Windowed
        property int moves: 0
        property int minimizes: 0
        property int toggles: 0
        property int closes: 0
        property int resizeEdges: 0
        function startSystemMove() { moves++ }
        function showMinimized() { minimizes++ }
        function toggleWindowMaximized() { toggles++ }
        function close() { closes++ }
        function startSystemResize(edges) { resizeEdges = edges }
    }
    Lunchpail.SettingsWindowHeader {
        id: header
        width: parent.width; height: 72
        applicationWindow: app
    }
    SignalSpy { id: settingsClosed; target: header; signalName: "closeSettingsRequested" }
    Lunchpail.LbDialog {
        id: dialog
        width: 700; height: 250
        x: 100; y: 30; padding: 0
        modal: true; focus: true
        closePolicy: Controls.Popup.CloseOnEscape
        header: Lunchpail.SettingsWindowHeader {
            applicationWindow: app
            onCloseSettingsRequested: dialog.close()
        }
        contentItem: Item {
            Lunchpail.WindowResizeFrame {
                id: resizeFrame
                applicationWindow: app
                parent: dialog.header.parent
                anchors.fill: parent
                z: 1100
            }
        }
    }
    function init() {
        header.width = test.width
        app.moves = 0; app.minimizes = 0; app.toggles = 0; app.closes = 0
        app.resizeEdges = 0
        settingsClosed.clear()
        dialog.close()
    }
    function test_window_actions_and_settings_close_remain_distinct() {
        mouseClick(findChild(header, "settingsMinimizeWindow"))
        mouseClick(findChild(header, "settingsMaximizeWindow"))
        mouseClick(findChild(header, "closeSettingsButton"))
        compare(app.minimizes, 1); compare(app.toggles, 1)
        compare(settingsClosed.count, 1); compare(app.closes, 0)
        mouseClick(findChild(header, "settingsCloseWindow"))
        compare(app.closes, 1)
    }
    function test_header_drags_the_window() {
        mouseClick(findChild(header, "settingsWindowDragArea"), 200, 20)
        compare(app.moves, 1)
    }
    function test_close_controls_stay_inside_narrow_header() {
        header.width = 650
        wait(30)
        for (const name of ["closeSettingsButton", "settingsMinimizeWindow", "settingsMaximizeWindow", "settingsCloseWindow"]) {
            const control = findChild(header, name)
            const point = control.mapToItem(header, 0, 0)
            verify(control.visible, name)
            verify(point.x >= 0 && point.x + control.width <= header.width, name)
        }
    }
    function test_modal_settings_close_button_and_escape() {
        dialog.open()
        tryVerify(() => dialog.visible)
        mouseClick(findChild(dialog.header, "closeSettingsButton"))
        tryVerify(() => !dialog.visible)
        dialog.open()
        tryVerify(() => dialog.visible)
        keyClick(Qt.Key_Escape)
        tryVerify(() => !dialog.visible)
    }
    function test_modal_settings_keeps_native_resize_edges_interactive() {
        dialog.open()
        tryVerify(() => dialog.visible)
        for (const entry of [["Top", Qt.TopEdge], ["Right", Qt.RightEdge], ["Bottom", Qt.BottomEdge],
                            ["Left", Qt.LeftEdge], ["BottomRight", Qt.BottomEdge | Qt.RightEdge]]) {
            const edge = findChild(resizeFrame, "windowResize" + entry[0])
            verify(edge)
            mouseClick(edge)
            compare(app.resizeEdges, entry[1], entry[0])
        }
        dialog.close()
    }
}
