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
    readonly property string phase: result.key === selectionKey ? result.phase || "" : ""
    readonly property int progress: result.key === selectionKey && result.progress !== undefined ? result.progress : -1
    readonly property bool pending: request.running
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
        onTriggered: if (controller.selectionKey) {
            // Gameplay snaps use the existing priority queue. Only a settled
            // selection requests media; spinning past games remains cheap.
            if (!controller.platform)
                controller.library.request_game_video(controller.gameId)
            controller.library.request_couch_theme(controller.platform ? "" : controller.gameId, controller.platform)
        }
    }
}
