"""Guard full-view bindings around the tested Couch theme selection policy."""
from pathlib import Path
import unittest


class CouchThemeWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qml = (Path(__file__).resolve().parents[1] / "qml" / "CouchModeView.qml").read_text()

    def test_selected_game_sources_and_preview_use_theme_policy(self):
        self.assertIn('themeVideoUrl: view.browsing.theme_video_url || ""', self.qml)
        self.assertIn('gameplayVideoUrl: view.browsing.video_url || ""', self.qml)
        self.assertIn("readonly property url previewVideoUrl: themeRequest.previewVideoUrl", self.qml)
        self.assertIn("videoKind: themeRequest.videoKind", self.qml)

    def test_platform_identity_refreshes_when_async_catalog_arrives(self):
        binding = self.qml.split("id: platformPresentation", 1)[1].split("onPlatformChanged:", 1)[0]
        self.assertIn("platformWheel.count", binding)
        self.assertIn("return platformWheel.nameAt(view.platformWheelIndex)", binding)
        browser = (Path(__file__).resolve().parents[1] / "qml" / "CouchPlatformBrowser.qml").read_text()
        name_lookup = browser.split("function nameAt(index)", 1)[1].split("function gameCountAt", 1)[0]
        self.assertIn("library.platform_revision", name_lookup)
        self.assertIn("library.filtered_platform_name_at(index)", name_lookup)
        self.assertIn('platform: view.platformWheelOpen ? platformPresentation.platform : ""', self.qml)


if __name__ == "__main__":
    unittest.main()
