import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Rectangle {
    id: header
    required property var applicationWindow
    property string saveStatus: "CHANGES SAVE AUTOMATICALLY"
    property bool saving: false
    signal closeSettingsRequested()
    signal setupRequested()
    implicitHeight: 72
    color: "#1a2230"
    border.color: "#3a495f"

    MouseArea {
        objectName: "settingsWindowDragArea"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: header.applicationWindow.startSystemMove()
        onDoubleClicked: header.applicationWindow.toggleWindowMaximized()
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24; anchors.rightMargin: 12
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 80
            spacing: 1
            Text { text: "SETTINGS"; color: "#f4f7fb"; font.pixelSize: 18; font.bold: true; font.letterSpacing: 0.8 }
            Text {
                Layout.fillWidth: true
                text: "Library, downloads, accounts, emulators, and presentation"
                color: "#8d99aa"; font.pixelSize: 10; elide: Text.ElideRight
            }
        }
        Text {
            visible: header.width >= 1100
            text: header.saveStatus
            color: header.saving ? "#62d6c6" : "#8d99aa"
            font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8
        }
        LbButton {
            visible: header.width >= 850
            text: "Setup guide"; flat: true
            onClicked: header.setupRequested()
        }
        LbButton {
            objectName: "closeSettingsButton"
            text: "Close settings"
            onClicked: header.closeSettingsRequested()
            Accessible.name: "Close settings"
            ToolTip.visible: hovered
            ToolTip.text: "Return to the library · Esc"
        }
        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 25; color: "#3a495f" }
        Row {
            spacing: 2
            WindowControlButton {
                objectName: "settingsMinimizeWindow"
                width: 38; height: 38
                icon.name: "window-minimize"; icon.source: "icons/window-minimize.svg"
                onClicked: header.applicationWindow.showMinimized()
                Accessible.name: "Minimize window"
                ToolTip.visible: hovered; ToolTip.text: "Minimize"
            }
            WindowControlButton {
                objectName: "settingsMaximizeWindow"
                width: 38; height: 38
                readonly property bool maximized: header.applicationWindow.visibility === Window.Maximized
                icon.name: maximized ? "window-restore" : "window-maximize"
                icon.source: maximized ? "icons/window-restore.svg" : "icons/window-maximize.svg"
                onClicked: header.applicationWindow.toggleWindowMaximized()
                Accessible.name: maximized ? "Restore window" : "Maximize window"
                ToolTip.visible: hovered; ToolTip.text: maximized ? "Restore" : "Maximize"
            }
            WindowControlButton {
                objectName: "settingsCloseWindow"
                width: 38; height: 38; destructive: true
                icon.name: "window-close"; icon.source: "icons/window-close.svg"
                onClicked: header.applicationWindow.close()
                Accessible.name: "Close Lunchpail window"
                ToolTip.visible: hovered; ToolTip.text: "Close Lunchpail"
            }
        }
    }
}
