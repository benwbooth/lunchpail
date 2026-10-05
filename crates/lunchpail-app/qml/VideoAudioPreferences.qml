import QtCore

Settings {
    category: "VideoAudio"
    property bool normalMuted: true
    property bool couchMuted: false

    function toggle(couchMode) {
        if (couchMode)
            couchMuted = !couchMuted
        else
            normalMuted = !normalMuted
        // Commit immediately, including when the app restarts before the
        // automatic property-save timer runs. Only change the active mode.
        setValue(couchMode ? "couchMuted" : "normalMuted",
                 couchMode ? couchMuted : normalMuted)
        sync()
    }
}
