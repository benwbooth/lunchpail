import QtQuick

// Presentation and routing for the details page's prominent launch/install
// action. Choosing Install still reviews the exact files before downloading.
QtObject {
    id: action
    required property var details
    property bool current: false
    property bool local: false
    property bool downloadable: false
    property string downloadState: ""
    property real downloadProgress: 0
    readonly property bool hasDownload: downloadState.length > 0
        && downloadState !== "IMPORTED" && downloadState !== "CANCELLED"
    readonly property string kind: !current || details.loading ? "loading"
        : details.game_running ? "stop"
        : details.launch_busy ? "cancel"
        : details.download_busy ? "queueing"
        : details.can_launch ? "play"
        : hasDownload ? "download"
        : local ? "setup"
        : downloadable ? "install" : "files"
    readonly property bool enabled: kind !== "loading" && kind !== "queueing"
        && !(kind === "stop" && details.session_stopping)
    readonly property string label: kind === "play" ? "Play"
        : kind === "install" ? "Install & play"
        : kind === "setup" ? "Set up play"
        : kind === "download" ? (downloadState === "FAILED" ? "Fix installation" : "View installation")
        : kind === "files" ? "Add game files"
        : kind === "stop" ? (details.session_stopping ? "Stopping…" : "Stop emulator")
        : kind === "cancel" ? "Cancel preparation"
        : kind === "queueing" ? "Adding installation…" : "Loading…"
    readonly property real progress: kind === "download" && downloadState === "DOWNLOADING"
        ? Math.max(0, Math.min(1, downloadProgress)) : -1
    readonly property string hint: kind === "play" ? "Installed and ready to play"
        : kind === "install" ? "Choose a version, then confirm the download"
        : kind === "setup" ? "Game files found · choose an emulator and finish setup"
        : kind === "files" ? "Add your game files to install and play"
        : kind === "loading" ? "Checking installation and play options"
        : kind === "queueing" ? "Adding the selected files to your downloads"
        : kind === "stop" ? (details.session_stopping ? "Waiting for the emulator to close" : "The emulator is currently running")
        : kind === "cancel" ? "Launch preparation is in progress"
        : downloadState === "DOWNLOADING" ? "Downloading · " + Math.round(progress * 100) + "% · open progress"
        : downloadState === "PAUSED" ? "Installation paused · resume this download"
        : downloadState === "FAILED" ? "Installation needs attention · open recovery options"
        : downloadState === "COMPLETE" ? "Files downloaded · open import status"
        : "Installation queued · open progress"
    signal requested(string kind)
    function activate() { if (enabled) requested(kind) }
}
