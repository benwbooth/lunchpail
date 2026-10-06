import QtQuick
import QtCore
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: testCase
    name: "VideoAudioPreferences"
    property int nextLocation: 0
    readonly property string locationPrefix: StandardPaths.writableLocation(StandardPaths.TempLocation)
                                              + "/lunchpail-video-audio-test-" + Date.now()

    function freshLocation() { return locationPrefix + "-" + (++nextLocation) + ".ini" }
    Component { id: preferencesComponent; Lunchpail.VideoAudioPreferences {} }
    Component { id: settingsComponent; Settings { category: "VideoAudio" } }

    function test_defaults_are_separate() {
        const prefs = createTemporaryObject(preferencesComponent, this, { location: freshLocation() })
        compare(prefs.gridMuted, true)
        compare(prefs.detailsMuted, true)
        compare(prefs.couchMuted, false)
    }

    function test_each_toggle_changes_only_its_global_scope_data() {
        return [{ tag: "grid", scope: "grid" }, { tag: "details", scope: "details" },
                { tag: "couch", scope: "couch" }]
    }

    function test_each_toggle_changes_only_its_global_scope(data) {
        const prefs = createTemporaryObject(preferencesComponent, this, { location: freshLocation() })
        const before = {grid: prefs.gridMuted, details: prefs.detailsMuted, couch: prefs.couchMuted}
        prefs.toggle(data.scope)
        for (const scope of ["grid", "details", "couch"])
            compare(prefs.muted(scope), scope === data.scope ? !before[scope] : before[scope])
        prefs.toggle(data.scope)
        for (const scope of ["grid", "details", "couch"])
            compare(prefs.muted(scope), before[scope])
    }

    function test_choices_are_saved_immediately_and_reloaded() {
        const location = freshLocation()
        const prefs = preferencesComponent.createObject(this, { location: location })
        prefs.setMuted("grid", false)
        prefs.setMuted("details", true)
        prefs.setMuted("couch", true)
        const reader = createTemporaryObject(settingsComponent, this, { location: location })
        compare(reader.value("gridMuted"), false)
        compare(reader.value("detailsMuted"), true)
        compare(reader.value("couchMuted"), true)
        prefs.destroy()
        wait(1)
        const restored = createTemporaryObject(preferencesComponent, this, { location: location })
        compare(restored.gridMuted, false)
        compare(restored.detailsMuted, true)
        compare(restored.couchMuted, true)
        restored.toggle("details")
        compare(reader.value("gridMuted"), false)
        compare(reader.value("detailsMuted"), false)
        compare(reader.value("couchMuted"), true)
    }

    function test_legacy_choice_seeds_both_scopes_once_data() {
        return [{tag: "muted", value: true, expected: true},
                {tag: "unmuted", value: false, expected: false},
                {tag: "serialized-false", value: "false", expected: false}]
    }

    function test_legacy_choice_seeds_both_scopes_once(data) {
        const location = freshLocation()
        const seed = createTemporaryObject(settingsComponent, this, { location: location })
        seed.setValue("normalMuted", data.value)
        seed.sync()
        const prefs = preferencesComponent.createObject(this, { location: location })
        compare(prefs.gridMuted, data.expected)
        compare(prefs.detailsMuted, data.expected)
        prefs.toggle("grid")
        prefs.destroy()
        wait(1)
        const restored = createTemporaryObject(preferencesComponent, this, { location: location })
        compare(restored.gridMuted, !data.expected)
        compare(restored.detailsMuted, data.expected)
    }

    function test_migration_does_not_overwrite_existing_scopes() {
        const location = freshLocation()
        const seed = createTemporaryObject(settingsComponent, this, { location: location })
        seed.setValue("normalMuted", true)
        seed.setValue("gridMuted", "false")
        seed.setValue("couchMuted", "false")
        seed.sync()
        const prefs = createTemporaryObject(preferencesComponent, this, { location: location })
        compare(prefs.gridMuted, false)
        compare(prefs.detailsMuted, true)
        compare(prefs.couchMuted, false)
    }

    function test_labels_describe_the_scope() {
        const prefs = createTemporaryObject(preferencesComponent, this, { location: freshLocation() })
        compare(prefs.toggleLabel("grid"), "Unmute all grid previews")
        compare(prefs.toggleLabel("details"), "Unmute all Game Media videos")
        prefs.toggle("grid")
        compare(prefs.toggleLabel("grid"), "Mute all grid previews")
        compare(prefs.toggleLabel("details"), "Unmute all Game Media videos")
    }
}
