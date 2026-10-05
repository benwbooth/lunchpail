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
    Component {
        id: modeComponent
        QtObject {
            required property var preferences
            property bool couchMode: false
            readonly property bool muted: couchMode ? preferences.couchMuted : preferences.normalMuted
        }
    }

    function test_defaults_are_separate() {
        const preferences = createTemporaryObject(preferencesComponent, this, { location: freshLocation() })
        compare(preferences.normalMuted, true)
        compare(preferences.couchMuted, false)
    }

    function test_toggles_and_mode_switches_do_not_change_other_mode() {
        const preferences = createTemporaryObject(preferencesComponent, this, { location: freshLocation() })
        const mode = createTemporaryObject(modeComponent, this, { preferences: preferences })
        compare(mode.muted, true)
        preferences.toggle(false)
        compare(mode.muted, false)
        compare(preferences.couchMuted, false)
        mode.couchMode = true
        compare(mode.muted, false)
        preferences.toggle(true)
        compare(mode.muted, true)
        compare(preferences.normalMuted, false)
        mode.couchMode = false
        compare(mode.muted, false)
        mode.couchMode = true
        compare(mode.muted, true)
    }

    function test_choices_are_saved_immediately_and_reloaded() {
        const location = freshLocation()
        const preferences = preferencesComponent.createObject(this, { location: location })
        preferences.toggle(false)
        preferences.toggle(true)
        const reader = createTemporaryObject(settingsComponent, this, { location: location })
        compare(reader.value("normalMuted"), false)
        compare(reader.value("couchMuted"), true)
        preferences.destroy()
        wait(1)
        const restored = createTemporaryObject(preferencesComponent, this, { location: location })
        compare(restored.normalMuted, false)
        compare(restored.couchMuted, true)
        restored.toggle(false)
        restored.toggle(true)
        compare(reader.value("normalMuted"), true)
        compare(reader.value("couchMuted"), false)
    }

    function test_false_from_a_previous_process_is_not_truthy() {
        const location = freshLocation()
        const seed = createTemporaryObject(settingsComponent, this, { location: location })
        seed.setValue("normalMuted", "false")
        seed.setValue("couchMuted", "false")
        seed.sync()
        const restored = createTemporaryObject(preferencesComponent, this, { location: location })
        compare(restored.normalMuted, false)
        compare(restored.couchMuted, false)
    }
}
