pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A ten-foot presentation, not a second desktop sidebar. Management tools
// open on demand; the library and its selected card remain underneath.
Rectangle {
    id: page
    required property var details
    property string gameTitle: ""
    property string platform: ""
    property url coverUrl: ""
    property url backgroundUrl: ""
    property url logoUrl: ""
    property string primaryAction: "Play"
    property string primaryHint: "Installed and ready to play"
    property string primaryKind: "play"
    property bool primaryEnabled: ready
    property real primaryProgress: -1
    property bool favorite: false
    property bool ready: false
    property color background: "#101620"
    property color panel: "#182230"
    property color ink: "#f4f7fb"
    property color muted: "#95a2b6"
    property color accent: "#62dac8"
    property int tabIndex: 0
    property int navigationArea: 0 // action rail, tabs, content
    property int actionIndex: 0
    property int toolIndex: 0
    readonly property real gutter: Math.max(24, Math.min(64, width * 0.035))
    readonly property var tabs: ["Overview", "Play & setup", "Media", "Activity", "Library"]
    readonly property var tools: tabIndex === 1 ? [
        { label: "Display & save states", hint: "Display shaders, bezels and automatic resume", key: "display" },
        { label: "Controllers", hint: "Players and button mappings", key: "controllers" },
        { label: "Translations & mods", hint: "Community patches and cheats", key: "mods" },
        { label: "RetroAchievements", hint: "Achievement mode and account", key: "achievements" },
        { label: "ROMs & save files", hint: "Versions, backups and uninstall", key: "files" },
        { label: "Emulator & launch", hint: "Runtime, defaults, launch profiles and PC setup", key: "launch" }
    ] : tabIndex === 2 ? [
        { label: "View artwork", hint: "Full-size artwork gallery", key: "artwork" },
        { label: "Watch video", hint: "Gameplay preview and playback controls", key: "video" },
        { label: "Find better media", hint: "Choose replacement artwork", key: "find-media" },
        { label: "Themes & system media", hint: "HyperSpin videos and system wheel artwork", key: "themes" },
        { label: "Manual & music", hint: "Cached media and downloads", key: "media" },
        { label: "3D box", hint: "Rotate and inspect the game box", key: "box3d" }
    ] : tabIndex === 4 ? [
        { label: "Edit information", hint: "Metadata, notes, tags and custom fields", key: "metadata" },
        { label: "Collections", hint: "Organize this game in your library", key: "collections" },
        { label: "Related games", hint: "More from this series and its creators", key: "related" },
        { label: "Catalog & links", hint: "Sources, release information and websites", key: "catalog" }
    ] : []
    readonly property var facts: {
        if (!ready) return []
        const fields = [["Released", "release_date"], ["Developer", "developer"],
            ["Publisher", "publisher"], ["Genre", "genre"], ["Players", "players"],
            ["Play mode", "play_mode"], ["Series", "series"], ["Region", "region"],
            ["Version", "version"], ["Age rating", "esrb"], ["Release type", "release_type"],
            ["Status", "release_status"], ["Rating", "rating"]]
        const result = []
        for (const field of fields) {
            const value = details[field[1]]
            if (value) result.push({label: field[0], value: String(value)})
        }
        if (details.cooperative && details.cooperative !== "unknown")
            result.push({label: "Co-op", value: details.cooperative === "yes" ? "Supported" : "Not supported"})
        return result
    }
    signal closeRequested()
    signal primaryRequested()
    signal favoriteRequested()
    signal versionsRequested()
    signal manageRequested(string section)

    objectName: "couchDetailsPage"
    color: background
    // Consume pointer events not handled by the page's controls, including
    // passive TapHandlers. The game wheel underneath must remain unchanged.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: event => { event.accepted = true }
    }
    Image {
        anchors.fill: parent; source: page.backgroundUrl
        asynchronous: true; fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(1920, 1080); opacity: 0.35
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: page.background }
            GradientStop { position: 0.55; color: Qt.rgba(page.background.r, page.background.g, page.background.b, 0.90) }
            GradientStop { position: 1; color: Qt.rgba(page.background.r, page.background.g, page.background.b, 0.48) }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: page.background }
        }
    }
    function reset() { tabIndex = 0; navigationArea = 0; actionIndex = 0; toolIndex = 0; overview.contentY = 0 }
    function chooseTab(index) { tabIndex = Math.max(0, Math.min(tabs.length - 1, index)); toolIndex = 0; overview.contentY = 0; toolScroll.contentY = 0 }
    onToolIndexChanged: {
        const item = toolRepeater.itemAt(toolIndex)
        if (item) toolScroll.contentY = Math.max(0, Math.min(toolScroll.contentHeight - toolScroll.height,
            item.y + item.height > toolScroll.contentY + toolScroll.height
            ? item.y + item.height - toolScroll.height : Math.min(item.y, toolScroll.contentY)))
    }
    function activateRail() {
        if (actionIndex === 0) { if (primaryEnabled) primaryRequested() }
        else if (actionIndex === 1) favoriteRequested()
        else if (ready) versionsRequested()
    }
    function handleNavigation(action) {
        if (action === "back") closeRequested()
        else if (action === "favorite") favoriteRequested()
        else if (action === "page_left" || action === "page_right") {
            chooseTab((tabIndex + (action === "page_left" ? tabs.length - 1 : 1)) % tabs.length)
            navigationArea = 1
        } else if (action === "left") {
            if (navigationArea === 1 && tabIndex > 0) chooseTab(tabIndex - 1)
            else if (navigationArea === 2 && tools.length && toolIndex % 2 === 1) toolIndex--
            else navigationArea = 0
        } else if (action === "right") {
            if (navigationArea === 0) navigationArea = 1
            else if (navigationArea === 1) chooseTab(Math.min(tabs.length - 1, tabIndex + 1))
            else if (tools.length) toolIndex = Math.min(tools.length - 1, toolIndex + 1)
        } else if (action === "up" || action === "down") {
            const step = action === "up" ? -1 : 1
            if (navigationArea === 0) actionIndex = Math.max(0, Math.min(2, actionIndex + step))
            else if (navigationArea === 1) { if (step > 0) navigationArea = 2 }
            else if (tools.length) {
                if (step < 0 && toolIndex < 2) navigationArea = 1
                else toolIndex = Math.max(0, Math.min(tools.length - 1, toolIndex + step * 2))
            } else if (step < 0 && overview.contentY <= 0) navigationArea = 1
            else overview.contentY = Math.max(0, Math.min(Math.max(0, overview.contentHeight - overview.height), overview.contentY + step * 110))
        } else if (action === "accept") {
            if (navigationArea === 0) activateRail()
            else if (navigationArea === 1) navigationArea = 2
            else if (tools.length && ready) manageRequested(tools[toolIndex].key)
            else if (tabIndex === 3 && ready) manageRequested("activity")
        } else if (action === "home") reset()
        else return false
        return true
    }

    RowLayout {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: page.gutter }
        spacing: 24
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7
            Text { text: page.platform.toUpperCase(); color: page.accent; font.pixelSize: 14; font.letterSpacing: 1.6; font.weight: Font.DemiBold }
            Text {
                Layout.fillWidth: true
                text: page.gameTitle; color: page.ink; font.pixelSize: 42; font.weight: Font.Bold
                minimumPixelSize: 22; fontSizeMode: Text.Fit; maximumLineCount: 2; wrapMode: Text.WordWrap
            }
        }
        LbButton {
            id: primaryButton
            objectName: "couchDetailsAction0"
            Layout.preferredWidth: Math.max(400, Math.min(840, page.width * 0.38))
            Layout.preferredHeight: Math.max(120, Math.min(160, page.height * 0.13))
            Layout.alignment: Qt.AlignVCenter
            text: page.primaryAction
            enabled: page.primaryEnabled
            highlighted: page.navigationArea === 0 && page.actionIndex === 0
            leftPadding: 24; rightPadding: 24; topPadding: 18; bottomPadding: 18
            Accessible.name: page.primaryAction + " · " + page.gameTitle
            Accessible.description: page.primaryHint
            background: Rectangle {
                radius: 18
                color: !primaryButton.enabled ? "#344454"
                    : primaryButton.down ? "#40bb76" : primaryButton.hovered ? "#83f4af" : "#61e394"
                border.color: primaryButton.highlighted || primaryButton.visualFocus ? "#f4fff8" : "#91f7b7"
                border.width: primaryButton.highlighted || primaryButton.visualFocus ? 4 : 1
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                    height: 5; radius: 2
                    visible: page.primaryProgress >= 0
                    color: "#319b61"
                    Rectangle { width: parent.width * Math.max(0, Math.min(1, page.primaryProgress)); height: parent.height; radius: 2; color: "#0a3220" }
                }
            }
            contentItem: RowLayout {
                spacing: 22
                Canvas {
                    id: primaryIcon
                    Layout.preferredWidth: 52; Layout.preferredHeight: 52
                    readonly property string kind: page.primaryKind
                    readonly property color ink: primaryButton.enabled ? "#082d1a" : "#bcc9d6"
                    onKindChanged: requestPaint()
                    onInkChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = ink; ctx.strokeStyle = ink; ctx.lineWidth = 5
                        ctx.lineCap = "round"; ctx.lineJoin = "round"
                        if (kind === "play") {
                            ctx.beginPath(); ctx.moveTo(10, 5); ctx.lineTo(46, 26); ctx.lineTo(10, 47); ctx.closePath(); ctx.fill()
                        } else if (kind === "install" || kind === "download") {
                            ctx.beginPath(); ctx.moveTo(26, 4); ctx.lineTo(26, 33); ctx.moveTo(13, 22); ctx.lineTo(26, 35); ctx.lineTo(39, 22)
                            ctx.moveTo(7, 39); ctx.lineTo(7, 47); ctx.lineTo(45, 47); ctx.lineTo(45, 39); ctx.stroke()
                        } else if (kind === "stop" || kind === "cancel") {
                            ctx.fillRect(9, 9, 34, 34)
                        } else if (kind === "setup" || kind === "files") {
                            ctx.beginPath(); ctx.moveTo(26, 8); ctx.lineTo(26, 44); ctx.moveTo(8, 26); ctx.lineTo(44, 26); ctx.stroke()
                        } else {
                            for (let x = 10; x <= 42; x += 16) { ctx.beginPath(); ctx.arc(x, 26, 4, 0, Math.PI * 2); ctx.fill() }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Text {
                        objectName: "couchDetailsPrimaryLabel"
                        Layout.fillWidth: true
                        text: page.primaryAction.toUpperCase()
                        color: primaryButton.enabled ? "#082d1a" : "#d3deea"
                        font.pixelSize: Math.max(36, Math.min(52, page.width / 36)); font.weight: Font.Black
                        minimumPixelSize: 24; fontSizeMode: Text.Fit; maximumLineCount: 1
                    }
                    Text {
                        Layout.fillWidth: true
                        text: page.primaryHint
                        color: primaryButton.enabled ? "#123f28" : "#bcc9d6"
                        font.pixelSize: 16; wrapMode: Text.WordWrap
                    }
                }
            }
            onClicked: { page.navigationArea = 0; page.actionIndex = 0; page.activateRail() }
        }
        LbRoundButton { text: "×"; implicitWidth: 48; implicitHeight: 48; Accessible.name: "Back to games"; onClicked: page.closeRequested() }
    }
    RowLayout {
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: help.top; margins: page.gutter }
        spacing: page.gutter
        ColumnLayout {
            id: rail
            Layout.preferredWidth: Math.min(320, page.width * 0.25)
            Layout.maximumWidth: Math.min(320, page.width * 0.25)
            Layout.fillHeight: true
            spacing: 12
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                Image {
                    id: cover
                    anchors.fill: parent; source: page.coverUrl; fillMode: Image.PreserveAspectFit
                    asynchronous: true; sourceSize: Qt.size(640, 900); cache: true; mipmap: true
                }
                Text { anchors.centerIn: parent; visible: cover.status !== Image.Ready; text: page.gameTitle.charAt(0); color: page.muted; font.pixelSize: 96 }
            }
            Image {
                Layout.fillWidth: true; Layout.preferredHeight: visible ? 46 : 0
                visible: status === Image.Ready
                source: page.logoUrl; fillMode: Image.PreserveAspectFit; asynchronous: true
                sourceSize: Qt.size(560, 160)
            }
            Repeater {
                model: [page.favorite ? "Remove favorite" : "Add favorite", "Other releases"]
                delegate: LbButton {
                    required property int index
                    required property string modelData
                    objectName: "couchDetailsAction" + (index + 1)
                    Layout.fillWidth: true; Layout.preferredHeight: 54
                    text: modelData
                    highlighted: page.navigationArea === 0 && page.actionIndex === index + 1
                    contentItem: LbButtonLabel { control: parent; pixelSize: 18 }
                    enabled: index !== 1 || (page.ready && page.details.variant_count > 1)
                    onClicked: { page.navigationArea = 0; page.actionIndex = index + 1; page.activateRail() }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 22
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: page.tabs
                    delegate: LbButton {
                        required property string modelData
                        required property int index
                        objectName: "couchDetailsTab" + index
                        Layout.fillWidth: true; Layout.preferredHeight: 48
                        text: modelData; highlighted: page.tabIndex === index
                        contentItem: LbButtonLabel { control: parent; pixelSize: 16 }
                        onClicked: { page.chooseTab(index); page.navigationArea = 1 }
                    }
                }
            }
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                MomentumFlickable {
                    id: overview
                    anchors.fill: parent; clip: true
                    visible: page.tabIndex === 0 || page.tabIndex === 3
                    contentWidth: width; contentHeight: copy.implicitHeight
                    ScrollBar.vertical: LbScrollBar { policy: ScrollBar.AsNeeded }
                    Column {
                        id: copy
                        width: overview.width - 20; spacing: 24
                        Text {
                            width: parent.width
                            text: !page.ready ? "Loading game information…" : page.tabIndex === 0
                                  ? (page.details.description || "No description is available for this release.")
                                  : page.details.activity_visible ? page.details.play_count + " plays · " + page.details.play_time : "You haven’t played this game yet."
                            color: page.ink; font.pixelSize: 21; lineHeight: 1.4; wrapMode: Text.WordWrap
                        }
                        GridLayout {
                            width: parent.width; columns: 2; columnSpacing: 32; rowSpacing: 22
                            Repeater {
                                model: page.tabIndex === 0 ? page.facts : !page.ready ? [] : [
                                    {label: "Last played", value: page.details.last_played || "Not yet"},
                                    {label: "Completion", value: (page.details.completion_state || "Not set").replace(/[-_]/g, " ")}]
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true; spacing: 5
                                    Text { text: parent.modelData.label.toUpperCase(); color: page.muted; font.pixelSize: 12; font.letterSpacing: 1.2 }
                                    Text { Layout.fillWidth: true; text: parent.modelData.value; color: page.ink; font.pixelSize: 19; wrapMode: Text.WordWrap }
                                }
                            }
                        }
                        Text {
                            width: parent.width; visible: page.tabIndex === 3 && page.ready && !!page.details.notes
                            text: page.details.notes || ""; color: page.muted; font.pixelSize: 19; wrapMode: Text.WordWrap
                        }
                        LbButton {
                            visible: page.tabIndex === 3; width: parent.width; height: 52
                            text: "Activity, completion & play sessions"; enabled: page.ready
                            onClicked: page.manageRequested("activity")
                        }
                    }
                }
                MomentumFlickable {
                    id: toolScroll
                    anchors.fill: parent; clip: true
                    visible: page.tools.length > 0
                    contentWidth: width; contentHeight: toolGrid.implicitHeight
                    ScrollBar.vertical: LbScrollBar { policy: ScrollBar.AsNeeded }
                    GridLayout {
                    id: toolGrid
                    width: parent.width - 16
                    columns: 2; columnSpacing: 16; rowSpacing: 16
                    Repeater {
                        id: toolRepeater
                        model: page.tools
                        delegate: LbButton {
                            required property int index
                            required property var modelData
                            objectName: "couchDetailsTool" + index
                            Layout.fillWidth: true; Layout.preferredHeight: Math.max(102, Math.min(132, (toolScroll.height - 32) / 3))
                            highlighted: page.navigationArea === 2 && page.toolIndex === index
                            enabled: page.ready
                            text: modelData.label
                            contentItem: Item {
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: 10
                                    Text { width: parent.width; text: parent.parent.parent.modelData.label; color: page.ink; font.pixelSize: 20; minimumPixelSize: 16; fontSizeMode: Text.Fit; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                                    Text { width: parent.width; text: parent.parent.parent.modelData.hint; color: page.muted; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                                }
                            }
                            onClicked: { page.navigationArea = 2; page.toolIndex = index; page.manageRequested(modelData.key) }
                        }
                    }
                    }
                }
            }
        }
    }
    Text {
        id: help
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
        text: "D-pad / arrows  Navigate     A / Enter  Select     LB / RB  Change tab     B / Escape  Back"
        color: page.muted; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter
    }
}
