import QtQuick
import QtQuick.Controls

// Always visible over artwork, including covers that are not yet favorites.
GameActionButton {
    id: control
    property bool favorite: false
    property string gameTitle: ""
    signal toggleRequested(bool favorite)

    objectName: "coverFavoriteButton"
    width: 36
    height: 36
    enabled: !busy
    iconName: "favorite"
    iconFilled: favorite
    selected: favorite
    keepIconWhenBusy: true
    showLabel: false
    text: favorite ? "Remove from Favorites" : "Add to Favorites"
    Accessible.name: (favorite ? "Remove from Favorites: " : "Add to Favorites: ") + gameTitle
    ToolTip.visible: hovered || visualFocus
    ToolTip.text: busy ? "Saving favorite…"
                      : favorite ? "Remove from Favorites" : "Add to Favorites"
    onClicked: toggleRequested(!favorite)
}
