"""Keep launch, local-save and backup notices on the same presentation path."""
from pathlib import Path
import unittest


class NotificationWiring(unittest.TestCase):
    def test_one_toast_for_all_save_events(self):
        app = Path(__file__).resolve().parents[1]
        qml = (app / "qml/Main.qml").read_text()
        self.assertEqual(qml.count("NotificationToast {"), 1)
        for old in ("saveSyncToast", "saveFileToast", "save_file_notice_success"):
            self.assertNotIn(old, qml)
        self.assertIn("gameDetails.save_file_notice_severity", qml)
        self.assertIn('root.notify(prefix + saveSync.message, "info", "save-sync", false)', qml)

    def test_launch_notices_are_info_not_failed_success(self):
        app = Path(__file__).resolve().parents[1]
        source = (app / "src/game_details_model.rs").read_text()
        launch = source.split(".and_then(|observation| observation.launch_notice())", 1)[1]
        self.assertRegex(launch, r'show_save_file_notice\(\s*generation,\s*&notice_game_id,\s*notice,\s*"info"')
        self.assertIn('if *success { "success" } else { "warning" }', source)

    def test_sync_announces_busy_before_starting_worker(self):
        app = Path(__file__).resolve().parents[1]
        source = (app / "src/save_sync_model.rs").read_text()
        start = source.split("fn start_sync_request(", 1)[1].split("let qt_thread", 1)[0]
        self.assertLess(start.index('set_status(qstring("busy"))'), start.index("bump_revision()"))


if __name__ == "__main__":
    unittest.main()
