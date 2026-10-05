import QtQuick
import QtQuick.Controls

// Status always belongs to the selected game, never another queue entry.
Item {
    id: status
    required property var library
    property string gameId: ""
    property string videoKind: ""
    property string themePhase: ""
    property int themeProgress: -1
    property string themeMessage: ""
    property bool selectionPending: false
    property string playbackError: ""
    property color ink: "#e7eef7"
    property color muted: "#9baabd"
    property color accent: "#6ee0c4"
    readonly property var queueRevision: [library.media_pending_count, library.media_active_title,
        library.media_active_progress, library.media_setup_required, library.media_revision]
    readonly property string gameplayState: {
        queueRevision
        return gameId ? library.automatic_video_state(gameId) : "idle"
    }
    readonly property string gameplayMessage: {
        queueRevision
        return gameId ? library.automatic_video_message(gameId) : ""
    }
    readonly property bool gameplayBusy: !videoKind && ["checking-setup", "queued", "downloading"].indexOf(gameplayState) >= 0
    readonly property bool themeBusy: ["queued", "finding", "downloading"].indexOf(themePhase) >= 0
    readonly property bool busy: selectionPending || gameplayBusy || themeBusy
    readonly property int progress: gameplayBusy
        ? (gameplayState === "downloading" ? library.media_active_progress : -1)
        : themeBusy ? themeProgress : -1
    readonly property string summary: {
        if (playbackError) return "Video could not play · artwork shown"
        let playing = videoKind === "theme" ? "GAME THEME" : videoKind === "gameplay" ? "GAMEPLAY VIDEO" : ""
        let activity = ""
        if (selectionPending && !playing) activity = "Loading selected game media…"
        else if (gameplayBusy) {
            activity = gameplayState === "queued" ? "Game video queued…"
                     : gameplayState === "checking-setup" ? "Checking video account…"
                     : library.media_active_progress > 0 ? "Downloading game video · " + library.media_active_progress + "%"
                     : "Finding game video…"
        } else if (!playing && gameplayState === "setup-required") activity = "Game videos need EmuMovies setup · open Settings"
        else if (!playing && gameplayMessage.indexOf("failed") >= 0) activity = "Game video download failed · reselect to retry"
        else if (themeBusy) activity = themePhase === "queued" ? "Game theme queued…"
                     : themeProgress > 0 ? "Downloading game theme · " + themeProgress + "%"
                     : "Finding game theme…"
        else if (!playing && (gameplayState === "unavailable" || themePhase === "unavailable")) activity = "No matching game video · artwork shown"
        else if (!playing && themePhase === "error") activity = "Game media download failed · reselect to retry"
        else if (!playing) activity = "Loading game media…"
        return playing && activity ? playing + "  ·  " + activity : playing || activity
    }
    implicitHeight: 22
    Accessible.role: Accessible.StaticText
    Accessible.name: summary
    Text {
        objectName: "couchMediaStatusLabel"
        anchors { left: parent.left; right: parent.right; top: parent.top }
        text: status.summary
        color: status.busy ? status.accent : status.muted
        font.pixelSize: 11
        font.weight: status.busy ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
    }
    InlineProgressBar {
        objectName: "couchMediaProgress"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 3
        visible: status.busy
        from: 0; to: 100
        value: Math.max(0, status.progress)
        indeterminate: status.progress <= 0
        trackColor: Qt.rgba(status.muted.r, status.muted.g, status.muted.b, 0.2)
        fillColor: status.accent
    }
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: [status.playbackError, status.gameplayMessage, status.themeMessage].filter(value => !!value).join("\n")
}
