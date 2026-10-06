import QtQuick
import QtQuick.Controls

Item {
    id: guard
    required property var overlayItem
    property var ignoredItem: null
    // Attached tooltips share this popup in a window. Exclude its visual item,
    // not all non-modal popups: menus and other workflows still block capture.
    readonly property var tooltipItem: ToolTip.toolTip.contentItem.parent
    readonly property bool blocked: {
        if (!overlayItem) return false
        for (let i = 0; i < overlayItem.children.length; ++i) {
            const item = overlayItem.children[i]
            if (item !== ignoredItem && item !== tooltipItem && item.visible
                    && item.width > 0 && item.height > 0) return true
        }
        return false
    }
}
