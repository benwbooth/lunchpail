import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: toast
    property var current: null
    property var pending: []
    property int displayDuration: 5000
    readonly property string message: current ? current.message : ""
    readonly property string severity: current ? current.severity : "info"
    readonly property bool showing: current !== null

    // Update a running operation in place. Keep completed notices visible,
    // and coalesce queued progress so it cannot appear after its completion.
    function post(message, severity, key, persistent) {
        if (!message || !String(message).trim()) return
        const entry = {message: String(message), severity: severity || "info",
                       key: key || "", persistent: Boolean(persistent)}
        if (!current || (entry.key && entry.key === current.key) || current.persistent) {
            if (entry.key) pending = pending.filter(item => item.key !== entry.key)
            present(entry)
            return
        }
        const next = pending.slice()
        const index = entry.key ? next.findIndex(item => item.key === entry.key) : -1
        if (index >= 0) next[index] = entry
        else next.push(entry)
        pending = next.slice(-8)
    }

    function present(entry) {
        hideTimer.stop()
        current = entry
        if (!entry.persistent) hideTimer.restart()
    }

    function dismiss() {
        hideTimer.stop()
        const next = pending.slice()
        if (next.length) {
            const entry = next.shift()
            pending = next
            present(entry)
        } else current = null
    }

    NotificationStyle { id: appearance; severity: toast.severity }
    Timer { id: hideTimer; interval: toast.displayDuration; onTriggered: toast.dismiss() }

    width: parent ? Math.max(0, Math.min(parent.width - 48, 760)) : 760
    height: Math.max(68, contents.implicitHeight + 28)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? parent.height - height - 58 + (showing ? 0 : 20) : 0
    visible: opacity > 0
    opacity: showing ? 1 : 0
    z: 1500
    radius: 12
    color: appearance.background
    border.color: appearance.accent
    border.width: 1
    Accessible.role: Accessible.AlertMessage
    Accessible.name: message
    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180 } }

    RowLayout {
        id: contents
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        Text {
            text: appearance.symbol
            color: appearance.accent
            font.pixelSize: 22
            font.weight: Font.DemiBold
            Layout.preferredWidth: 24
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.fillWidth: true
            text: toast.message
            textFormat: Text.PlainText
            color: "#f4f7fb"
            wrapMode: Text.Wrap
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        LbButton {
            text: "×"
            flat: true
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            Accessible.name: "Dismiss notification"
            onClicked: toast.dismiss()
        }
    }
}
