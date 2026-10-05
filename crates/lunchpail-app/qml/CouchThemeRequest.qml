import QtQuick

// One debounced selection owns the shared game/system video request queue.
Item {
    id: controller
    required property var library
    property bool active: false
    property string gameId: ""
    property string platform: ""
    property int delay: 320
    readonly property string selectionKey: !active ? "" : platform ? "platform:" + platform
                                                                 : gameId ? "game:" + gameId : ""
    readonly property var result: JSON.parse(library.couch_theme_status_json || "{}")
    readonly property string status: result.key === selectionKey ? result.status || "" : ""
    function reconcile() {
        request.stop()
        library.cancel_couch_theme()
        if (selectionKey) request.restart()
    }
    onSelectionKeyChanged: reconcile()
    Component.onCompleted: reconcile()
    Timer {
        id: request
        interval: controller.delay
        onTriggered: if (controller.selectionKey)
            controller.library.request_couch_theme(controller.platform ? "" : controller.gameId, controller.platform)
    }
}
