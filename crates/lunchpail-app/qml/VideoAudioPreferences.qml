import QtCore
import QtQml

Settings {
    id: preferences
    category: "VideoAudio"
    property bool gridMuted: true
    property bool detailsMuted: true
    property bool couchMuted: false

    Component.onCompleted: {
        // Seed each new desktop scope from the old shared choice once. Never
        // overwrite an independently saved choice on subsequent starts.
        const legacy = value("normalMuted", true)
        const legacyMuted = legacy === true || legacy === "true" || legacy === 1
        for (const key of ["gridMuted", "detailsMuted"]) {
            if (value(key, null) === null) {
                preferences[key] = legacyMuted
                setValue(key, legacyMuted)
            }
        }
        sync()
    }

    function keyForScope(scope) {
        if (["grid", "details", "couch"].indexOf(scope) < 0)
            throw new Error("Unknown video audio scope: " + scope)
        return scope + "Muted"
    }

    function muted(scope) { return preferences[keyForScope(scope)] }

    function setMuted(scope, isMuted) {
        const key = keyForScope(scope)
        preferences[key] = isMuted
        // Commit immediately, including when the app restarts before the
        // automatic property-save timer runs. Only change this surface.
        setValue(key, isMuted)
        sync()
    }

    function toggle(scope) { setMuted(scope, !muted(scope)) }

    function toggleLabel(scope) {
        const surface = scope === "grid" ? "all grid previews"
                      : scope === "details" ? "all Game Media videos" : "all Couch videos"
        return (muted(scope) ? "Unmute " : "Mute ") + surface
    }
}
