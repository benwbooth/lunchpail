"""Guard always-visible Couch controls; the native hover probe tests behavior."""
from pathlib import Path
import unittest


class CouchControlsWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qml = (Path(__file__).resolve().parents[1] / "qml" / "CouchModeView.qml").read_text()

    def test_no_pointer_dependent_auto_hide_state(self):
        self.assertNotIn("wheelBrowseOnly", self.qml)
        self.assertNotIn("ToolbarHover", self.qml)

    def test_headers_categories_and_actions_have_no_visibility_gate(self):
        for name in ("couchHeaderActions", "couchPlatformHeader", "couchCategories", "couchPrimaryActions"):
            properties = self.qml.split(f'objectName: "{name}"', 1)[1].split("{", 1)[0]
            self.assertNotIn("visible:", properties, name)

    def test_preview_controls_only_follow_media_and_page_visibility(self):
        controls = self.qml.split("id: backgroundVideoControls", 1)[1].split("CouchActionButton", 1)[0]
        self.assertIn("visible: view.hasPreviewVideo && !view.overlayOpen && !view.platformWheelOpen", controls)
        self.assertNotIn("hover", controls.lower())


if __name__ == "__main__":
    unittest.main()
