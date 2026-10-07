import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: testCase
    name: "ExpandableDescription"
    when: windowShown
    visible: true
    width: 900; height: 800

    readonly property string longParagraph: "Explore the world, solve puzzles, and discover hidden secrets. ".repeat(12)
    Component {
        id: descriptionComponent
        Lunchpail.ExpandableDescription { width: 320 }
    }

    function test_short_descriptions_need_no_toggle_data() {
        return [{tag: "empty", text: ""}, {tag: "one-paragraph", text: "A short game description."}]
    }
    function test_short_descriptions_need_no_toggle(data) {
        const item = createTemporaryObject(descriptionComponent, this, {text: data.text})
        waitForRendering(item)
        verify(!item.canExpand)
        verify(!findChild(item, "descriptionToggle").visible)
        compare(findChild(item, "descriptionText").text, data.text)
        item.toggle()
        verify(!item.expanded)
    }
    function test_long_paragraph_expands_and_collapses() {
        const item = createTemporaryObject(descriptionComponent, this, {text: longParagraph})
        const body = findChild(item, "descriptionText")
        const button = findChild(item, "descriptionToggle")
        tryCompare(item, "canExpand", true)
        verify(!item.expanded)
        compare(body.lineCount, 4)
        verify(body.truncated)
        const collapsedHeight = item.height
        mouseClick(button)
        compare(item.expanded, true)
        compare(button.text, "Less")
        tryVerify(() => item.height > collapsedHeight)
        verify(!body.truncated)
        compare(body.text, longParagraph.trim())
        mouseClick(button)
        compare(item.expanded, false)
        compare(button.text, "More…")
        tryCompare(item, "height", collapsedHeight)
    }
    function test_multiple_paragraphs_stop_at_first_break_data() {
        return [{tag: "unix", separator: "\n\n"}, {tag: "windows", separator: "\r\n\r\n"},
                {tag: "blank-space", separator: "\n  \n"}]
    }
    function test_multiple_paragraphs_stop_at_first_break(data) {
        const text = "First paragraph." + data.separator + "Second paragraph."
        const item = createTemporaryObject(descriptionComponent, this, {text: text})
        const body = findChild(item, "descriptionText")
        verify(item.canExpand)
        compare(body.text, "First paragraph.")
        item.toggle()
        verify(body.text.includes("Second paragraph."))
        item.toggle()
        compare(body.text, "First paragraph.")
    }
    function test_keyboard_toggle() {
        const item = createTemporaryObject(descriptionComponent, this, {text: "First.\n\nSecond."})
        const button = findChild(item, "descriptionToggle")
        button.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(item.expanded, true)
        keyClick(Qt.Key_Space)
        compare(item.expanded, false)
    }
    function test_game_or_description_change_resets_expansion() {
        const item = createTemporaryObject(descriptionComponent, this, {text: longParagraph, contentKey: "game-1"})
        tryCompare(item, "canExpand", true)
        item.toggle()
        verify(item.expanded)
        item.contentKey = "game-2"
        verify(!item.expanded)
        item.toggle()
        verify(item.expanded)
        item.text = "Different first paragraph.\n\nDifferent second paragraph."
        verify(!item.expanded)
    }
    function test_overflow_reacts_to_width_and_font() {
        const item = createTemporaryObject(descriptionComponent, this, {
            text: "A moderately long description with enough words to wrap over four lines in a narrow details panel.", width: 90
        })
        tryCompare(item, "canExpand", true)
        item.width = 800
        tryCompare(item, "canExpand", false)
        item.width = 320
        item.font.pixelSize = 32
        tryCompare(item, "canExpand", true)
    }
    function test_metadata_is_plain_text() {
        const text = "A <b>literal title</b> with an <img src='https://example.invalid/image.png'> tag."
        const item = createTemporaryObject(descriptionComponent, this, {text: text})
        const body = findChild(item, "descriptionText")
        compare(body.textFormat, Text.PlainText)
        compare(body.text, text)
    }
}
