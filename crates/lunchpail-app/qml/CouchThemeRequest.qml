import QtQuick

// One debounced selection owns the shared game/system video request queue.
Item {
    id: controller
    required property var library
    property bool active: false
    property string gameId: ""
    property string platform: ""
    property url themeVideoUrl: ""
    property url gameplayVideoUrl: ""
    property int delay: 320
    property string fallbackRequestedKey: ""
    readonly property string selectionKey: !active ? "" : platform ? "platform:" + platform
                                                                 : gameId ? "game:" + gameId : ""
    readonly property var result: JSON.parse(library.couch_theme_status_json || "{}")
    readonly property string status: result.key === selectionKey ? result.status || "" : ""
    readonly property string phase: result.key === selectionKey ? result.phase || "" : ""
    readonly property int progress: result.key === selectionKey && result.progress !== undefined ? result.progress : -1
    readonly property bool pending: request.running
    readonly property bool gameSelection: active && !!gameId && !platform
    readonly property bool themeAvailable: themeVideoUrl.toString().length > 0
    readonly property bool gameplayFallbackAllowed: gameSelection && !themeAvailable
        && !pending && ["unavailable", "setup-required", "error"].indexOf(phase) >= 0
    readonly property url previewVideoUrl: !gameSelection ? ""
        : themeAvailable ? themeVideoUrl : gameplayFallbackAllowed ? gameplayVideoUrl : ""
    readonly property string videoKind: previewVideoUrl.toString().length === 0 ? ""
        : themeAvailable ? "theme" : "gameplay"

    function requestGameplayFallback() {
        if (!gameplayFallbackAllowed || gameplayVideoUrl.toString().length > 0
                || fallbackRequestedKey === selectionKey)
            return
        fallbackRequestedKey = selectionKey
        library.request_game_video(gameId)
    }

    function reconcile() {
        request.stop()
        fallbackRequestedKey = ""
        library.cancel_couch_theme()
        if (selectionKey && (platform || !themeAvailable)) request.restart()
    }
    onSelectionKeyChanged: reconcile()
    onPhaseChanged: Qt.callLater(requestGameplayFallback)
    onPendingChanged: Qt.callLater(requestGameplayFallback)
    onGameplayVideoUrlChanged: Qt.callLater(requestGameplayFallback)
    onThemeVideoUrlChanged: {
        if (gameSelection && themeAvailable) {
            request.stop()
            library.cancel_couch_theme()
        }
    }
    Component.onCompleted: reconcile()
    Timer {
        id: request
        interval: controller.delay
        onTriggered: if (controller.selectionKey) {
            // Animated themes get the first lookup and transfer. Gameplay is
            // requested only after that lookup cannot provide a theme.
            controller.library.request_couch_theme(controller.platform ? "" : controller.gameId, controller.platform)
        }
    }
}
