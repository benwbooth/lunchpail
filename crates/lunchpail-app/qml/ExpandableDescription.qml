import QtQuick

// Keep the overview compact without losing the full catalog description.
Column {
    id: root
    property string text: ""
    property string contentKey: ""
    property bool expanded: false
    property int previewLines: 4
    property alias font: description.font
    property alias color: description.color
    property alias lineHeight: description.lineHeight
    property color linkColor: "#ffcb84"
    property bool highlighted: false
    property int toggleHeight: 28
    readonly property string normalizedText: text.replace(/\r\n?/g, "\n").trim()
    readonly property string firstParagraph: normalizedText.split(/\n\s*\n/)[0]
    readonly property bool canExpand: normalizedText.length > firstParagraph.length
                                      || previewMeasure.truncated
    signal toggled()

    spacing: 4
    onTextChanged: expanded = false
    onContentKeyChanged: expanded = false
    onCanExpandChanged: { if (!canExpand) expanded = false }

    function toggle() {
        if (!canExpand) return
        expanded = !expanded
        toggled()
    }

    // Measure the collapsed text independently so the toggle remains available
    // while expanded, and re-evaluate it when the panel width/font changes.
    Text {
        id: previewMeasure
        visible: false
        width: root.width
        text: root.firstParagraph
        textFormat: Text.PlainText
        font: description.font
        lineHeight: description.lineHeight
        wrapMode: Text.Wrap
        maximumLineCount: root.previewLines
        elide: Text.ElideRight
    }
    Text {
        id: description
        objectName: "descriptionText"
        width: root.width
        text: root.expanded ? root.normalizedText : root.firstParagraph
        textFormat: Text.PlainText
        color: "#c0c8d4"
        font.pixelSize: 12
        lineHeight: 1.35
        wrapMode: Text.Wrap
        maximumLineCount: root.expanded ? 2147483647 : root.previewLines
        elide: root.expanded ? Text.ElideNone : Text.ElideRight
    }
    LbButton {
        id: toggleButton
        objectName: "descriptionToggle"
        visible: root.canExpand
        text: root.expanded ? "Less" : "More…"
        flat: true
        highlighted: root.highlighted
        height: root.toggleHeight
        leftPadding: 4
        rightPadding: 4
        font.pixelSize: description.font.pixelSize
        contentItem: LbButtonLabel {
            control: toggleButton
            color: root.linkColor
            pixelSize: description.font.pixelSize
        }
        Accessible.name: root.expanded ? "Collapse game description" : "Expand game description"
        Accessible.description: root.expanded ? "Showing the full description" : "Showing a short preview"
        onClicked: root.toggle()
    }
}
