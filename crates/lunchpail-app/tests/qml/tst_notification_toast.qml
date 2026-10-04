import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: testCase
    name: "NotificationToast"
    width: 900
    height: 500
    visible: true
    when: windowShown

    Component { id: component; Lunchpail.NotificationToast {} }
    Lunchpail.NotificationStyle { id: appearance }

    function test_first_launch_is_informational_and_times_out() {
        const toast = createTemporaryObject(component, testCase, {displayDuration: 50})
        toast.post("No previous saves yet. Starting a new game.", "info", "save-files", false)
        compare(toast.severity, "info")
        verify(toast.showing)
        appearance.severity = toast.severity
        compare(appearance.symbol, "i")
        compare(appearance.accent, "#9fb9d3")
        tryCompare(toast, "showing", false)
    }

    function test_progress_is_replaced_by_its_outcome() {
        const toast = createTemporaryObject(component, testCase)
        toast.post("Checking backup…", "info", "save-sync", true)
        toast.post("Saves synchronized", "success", "save-sync", false)
        compare(toast.message, "Saves synchronized")
        compare(toast.severity, "success")
        compare(toast.pending.length, 0)
        verify(!toast.current.persistent)
    }

    function test_save_confirmation_is_not_hidden_by_backup_progress() {
        const toast = createTemporaryObject(component, testCase)
        toast.post("Save state written", "success", "save-files", false)
        toast.post("Backing up saves…", "info", "save-sync", true)
        toast.post("Backup saved to /folder/lunchpail/saves", "success", "save-sync", false)
        compare(toast.message, "Save state written")
        compare(toast.pending.length, 1)
        toast.dismiss()
        compare(toast.message, "Backup saved to /folder/lunchpail/saves")
        verify(!toast.current.persistent)
        toast.dismiss()
        verify(!toast.showing)
    }

    function test_failure_and_cancel_replace_busy_state() {
        const toast = createTemporaryObject(component, testCase)
        toast.post("Checking saves…", "info", "save-sync", true)
        toast.post("Backup failed", "warning", "save-sync", false)
        compare(toast.severity, "warning")
        appearance.severity = toast.severity
        compare(appearance.symbol, "!")
        toast.post("Checking saves…", "info", "save-sync", true)
        toast.post("Sync cancelled", "info", "save-sync", false)
        compare(toast.message, "Sync cancelled")
        verify(!toast.current.persistent)
        compare(toast.pending.length, 0)
    }

    function test_interrupting_progress_does_not_repeat_a_queued_notice() {
        const toast = createTemporaryObject(component, testCase)
        toast.post("Previous game saved", "success", "save-files", false)
        toast.post("Checking backup…", "info", "save-sync", true)
        toast.post("Another notice", "info", "other", false)
        toast.dismiss()
        toast.post("Updated notice", "success", "other", false)
        compare(toast.message, "Updated notice")
        compare(toast.pending.length, 0)
    }

    function test_long_paths_wrap_and_styles_keep_the_same_layout() {
        const toast = createTemporaryObject(component, testCase,
                                            {width: 520, x: 0, y: 0, displayDuration: 60000})
        const styles = ["info", "success", "warning"]
        const messages = ["Faxanadu: No previous saves yet. Starting a new game with auto-save enabled.",
                          "Faxanadu: Save backup synchronized to /home/player/Cloud Drive/lunchpail/saves/v1/retroarch-core-fceumm/linux/current (original filenames)",
                          "Faxanadu: Save backup failed. Check your connection and try again."]
        for (let i = 0; i < styles.length; ++i) {
            toast.post(messages[i], styles[i], "save-sync", false)
            tryCompare(toast, "opacity", 1)
            verify(toast.height >= 68)
            verify(toast.height < 240)
            // Capture the containing scene after the layout/animation frame;
            // grabbing an animated child can capture its previous position.
            wait(300)
            grabImage(testCase).save("/tmp/lunchpail-notification-" + styles[i] + ".png")
        }
    }
}
