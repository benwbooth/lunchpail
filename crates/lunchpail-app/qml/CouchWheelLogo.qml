import QtQuick

// A wheel entry is one cached texture (or plain text while art is missing).
// Keep card chrome, favorites, reflections, and selection animations out of
// these frequently recycled delegates. PathView owns every moving transform.
Item {
    id: logo
    objectName: "couchWheelLogo"
    required property string title
    required property url source
    property color ink: "white"
    property bool selected: false
    readonly property bool artworkReady: artwork.status === Image.Ready
    Image {
        id: artwork
        anchors.fill: parent
        source: logo.source
        sourceSize: Qt.size(768, 384)
        asynchronous: true
        cache: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
    }
    Text {
        anchors.fill: parent
        anchors.margins: 4
        visible: !logo.artworkReady
        text: logo.title
        textFormat: Text.PlainText
        color: logo.ink
        style: Text.Outline
        styleColor: "#10131b"
        font.pixelSize: 54
        font.weight: Font.Black
        minimumPixelSize: 18
        fontSizeMode: Text.Fit
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    Accessible.role: Accessible.ListItem
    Accessible.name: title
    Accessible.selected: selected
}
