"""Keep both pane resize highlights full-height in every pointer state."""
from pathlib import Path
import unittest


class ResizeDividerWiring(unittest.TestCase):
    def test_both_dividers_keep_the_full_edge_highlighted_without_animation(self):
        qml = (Path(__file__).resolve().parents[1] / "qml" / "Main.qml").read_text()
        for pane in ("sidebar", "details"):
            with self.subTest(pane=pane):
                handle = qml.split(f"id: {pane}ResizeHandle", 1)[1]
                highlight = handle.split("Rectangle {", 1)[1].split("HoverHandler", 1)[0]
                self.assertRegex(highlight, r"(?m)^\s*height: parent\.height\s*$")
                self.assertNotRegex(highlight, r"Behavior\s+on\s+height|Animation|Timer|states:")
                self.assertIn(f"{pane}ResizeMouse.pressed ? root.accent", highlight)
                self.assertIn(f"{pane}ResizeHover.hovered ? root.accentCool : root.line", highlight)


if __name__ == "__main__":
    unittest.main()
