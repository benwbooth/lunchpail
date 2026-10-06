pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
    id: view

    required property var library
    required property var details
    required property var gamepad
    required property var downloadQueue
    required property var speech
    property var assistant: null
    property var speechOutput: null
    readonly property var conversationConfig: assistant ? JSON.parse(assistant.config_json || "{}") : ({})
    readonly property bool assistantSpeaking: !!speechOutput && speechOutput.speaking
    property bool conversationCoolingDown: false
    property var ai: null
    property bool windowActive: true
    property string installAction: ""
    property string searchText: ""
    property bool searchOpen: false
    property bool sfxEnabled: true
    property real sfxVolume: 0.22
    readonly property string movementCue: cinematicWheel ? "wheel" : wallView ? "wall" : albumView ? "flow" : "move"
    signal searchRequested(string text)
    readonly property bool audioSuppressedForVoice: handsFreeController.capturingCommand
        || searchOverlay.microphoneBusy || assistantSpeaking
    readonly property var handsFreeSetupController: handsFreeSetup
    readonly property bool microphoneEnabled: !!ai && ai.hands_free
    readonly property string handsFreeLabel: !microphoneEnabled ? "Mic off"
        : !handsFreeSetup.ready ? "Set up mic"
        : speech.faulted ? "Mic error" : "Mic on"
    readonly property string handsFreePauseReason: !assistant || !assistant.ready ? "Assistant setup needed"
        : !speech.ready ? "Speech model setup needed"
        : speech.faulted ? speech.status
        : !active || !visible ? "Couch mode is not active"
        : !windowActive ? "Lunchpail is not focused"
        : details.game_running ? "A game is running"
        : modelInstall.visible || handsFreeSetup.pending ? "Microphone setup is open"
        : launchStatusOverlayOpen ? "Game launch is open"
        : searchOverlay.microphoneBusy ? "Push-to-talk is active"
        : assistant.busy ? "Processing your request"
        : assistantSpeaking ? "Speaking a reply"
        : conversationCoolingDown ? "Waiting for reply audio to finish"
        : speech.busy && !speech.listening ? "Processing speech" : ""
    readonly property string handsFreeHint: (handsFreeSetup.pending ? "Cancel microphone setup"
        : !handsFreeSetup.ready ? "Set up assistant microphone"
        : ai && ai.hands_free ? "Turn microphone off" : "Turn microphone on")
        + " · F4" + (ai && ai.hands_free && handsFreePauseReason ? " · " + handsFreePauseReason : "")
    readonly property bool handsFreeAllowed: !!ai && ai.hands_free && active && visible && windowActive
        && !details.game_running && !launchStatusOverlayOpen
        && !searchOverlay.microphoneBusy && !modelInstall.visible && !handsFreeSetup.pending
        && !!assistant && assistant.ready && !assistant.busy && !assistantSpeaking && !conversationCoolingDown
    function acceptVoiceRequest(text) {
        speech.cancel()
        if (!assistant || !assistant.ready) {
            searchOverlay.askMode = true
            searchOverlay.preserveRequest(text)
            openSearch(text, false)
            handsFreeSetup.request()
        } else assistant.ask(text)
    }
    CouchHandsFreeController {
        id: handsFreeController
        speech: view.speech
        allowed: view.handsFreeAllowed
        onSearchRequested: text => view.acceptVoiceRequest(text)
    }
    Timer { id: voiceCooldown; interval: 900; onTriggered: view.conversationCoolingDown = false }
    onAssistantSpeakingChanged: {
        conversationCoolingDown = true
        if (!assistantSpeaking) voiceCooldown.restart()
        else voiceCooldown.stop()
    }
    Connections {
        target: view.assistant; ignoreUnknownSignals: true
        function onBusyChanged() {
            if (!view.assistant.busy) { view.conversationCoolingDown = true; voiceCooldown.restart() }
        }
    }
    function toggleHandsFree() {
        if (!ai) return
        handsFreeSetup.toggle()
    }
    HandsFreeSetup {
        id: handsFreeSetup
        ai: view.ai
        assistant: view.assistant
        onStoppedListening: view.speech.cancel()
        onSettingsRequested: view.settingsRequested("local-ai")
        onEnabledListening: {
            view.speech.refresh()
            view.speech.faulted = false
            handsFreeController.reconcile()
        }
    }
    LocalModelInstall {
        id: modelInstall
        ai: view.ai
        onReady: {
            view.speech.refresh()
            if (view.assistant) view.assistant.refresh()
            if (view.installAction === "assistant") searchOverlay.submit()
            else searchOverlay.microphone()
            view.installAction = ""
        }
        onDeclined: view.installAction = ""
    }
    readonly property bool feedbackReady: feedback.ready
    readonly property var soundFeedback: feedback
    readonly property var searchPanel: searchOverlay
    readonly property var installDialog: modelInstall
    property bool active: false
    property bool inputEnabled: true
    property var pendingSc2Actions: []
    property int navigationZone: 2
    property int categoryIndex: 0
    property int actionIndex: 0
    property bool platformWheelOpen: false
    property int platformWheelIndex: 0
    property bool collectionWheelOpen: false
    property int collectionWheelIndex: 0
    property bool variantWheelOpen: false
    property int variantWheelIndex: 0
    property bool attractOpen: false
    property bool attractProbeEnabled: false
    property string attractReason: "manual"
    property real attractProgress: 0
    property bool launchStatusOverlayOpen: false
    property bool launchSessionObserved: false
    property bool launchCompletionPending: false
    property bool downloadOverlayOpen: false
    property bool overlayOpen: false
    property string overlayMode: "details"
    readonly property var detailsPage: nativeDetails.item
    property int menuActionIndex: 0
    property string preferredGameId: ""
    property string currentFilterKey: ""
    property string currentPlatformName: ""
    property string selectedGameId: ""
    property string loadedGameId: ""
    property int selectedDatabaseId: 0
    property double selectedMediaId: 0
    property double heroMediaId: 0
    property bool videoMuted: false
    signal videoMuteRequested()
    signal videoRequested(url source)
    signal systemMediaRequested(string platform)
    CouchThemeRequest {
        id: themeRequest
        library: view.library
        active: view.active && !view.details.game_running
        gameId: view.selectedGameId
        platform: view.platformWheelOpen ? platformPresentation.platform : ""
        themeVideoUrl: view.browsing.theme_video_url || ""
        gameplayVideoUrl: view.browsing.video_url || ""
    }
    readonly property var previewRecord: JSON.parse(library.couch_preview_json || "{}")
    readonly property var browsing: Object.assign({
        game_id: "", description: "", release_date: "", genre: "", players: "",
        cooperative: "", rating: "", soundtrack_available: false,
        soundtrack_url: "", soundtrack_title: "", video_url: "", theme_video_url: ""
    }, previewRecord.game_id === selectedGameId ? previewRecord : {},
       { game_running: details.game_running, title: selectedTitle })
    property string selectedTitle: ""
    property string selectedPlatform: ""
    property bool selectedLocal: false
    property bool selectedDownloadable: false
    property int mediaRevision: library.media_revision
    onMediaRevisionChanged: if (active && selectedGameId) previewRefresh.restart()
    readonly property color background: library.couch_theme_background
    readonly property color panel: library.couch_theme_panel
    readonly property color panelRaised: library.couch_theme_panel_raised
    readonly property color ink: library.couch_theme_ink
    readonly property color muted: library.couch_theme_muted
    readonly property color accent: library.couch_theme_accent
    readonly property color accentCool: library.couch_theme_accent_cool
    readonly property color playGreen: "#5ee391"
    readonly property color danger: library.couch_theme_danger
    readonly property int cardRadius: library.couch_theme_card_radius
    readonly property real heroScrimOpacity: library.couch_theme_hero_scrim_percent / 100.0
    readonly property bool cinematicWheel: library.couch_view_style === "wheel"
    readonly property bool wheelBrowseOnly: cinematicWheel && navigationZone === 2
        && !wheelToolbarHover.hovered && !platformToolbarHover.hovered
    readonly property bool wallView: library.couch_view_style === "wall"
    readonly property bool albumView: library.couch_view_style === "album"
    // A system theme belongs to the system browser, never to a selected game.
    readonly property url previewVideoUrl: themeRequest.previewVideoUrl
    readonly property bool hasPreviewVideo: previewVideoUrl.toString().length > 0
    readonly property var gameVideoPreview: couchVideo
    readonly property var systemVideoPreview: platformVideo
    readonly property var gameBrowser: shelf
    readonly property var platformBrowser: platformWheel
    readonly property bool entryPending: entrySelection.pending
    CouchEntrySelection {
        id: entrySelection
        library: view.library
        browser: shelf
        active: view.active
        onSettled: {
            view.loadedGameId = ""
            view.loadCurrentGame()
        }
    }
    function beginGameHandoff(gameId, platform) {
        entrySelection.begin(gameId, platform)
        selectedGameId = gameId
        selectedPlatform = platform
        selectedTitle = library.display_title_for_game(gameId) || (details.game_id === gameId ? details.title : "")
        selectedDatabaseId = library.database_id_for_game(gameId)
        selectedMediaId = library.media_id_for_game(gameId)
        heroMediaId = selectedMediaId
        selectedLocal = library.local_for_game(gameId)
        selectedDownloadable = library.downloadable_for_game(gameId)
        loadedGameId = ""
        library.request_couch_preview(gameId)
    }
    readonly property var viewStyles: ["wheel", "shelf", "wall", "album"]
    readonly property var viewLabels: ["Logo wheel", "Cover shelf", "Cover wall", "Cover flow"]
    readonly property string viewLabel: viewLabels[Math.max(0, viewStyles.indexOf(library.couch_view_style))]
    readonly property int menuActionCount: 9
    readonly property var categories: [
        { label: "All games", key: "" },
        { label: "Platforms", key: "platform" },
        { label: "Collections", key: "collections" },
        { label: "My collection", key: "local" },
        { label: "Minerva", key: "downloadable" },
        { label: "Favorites", key: "favorites" },
        { label: "Recent", key: "recent" }
    ]
    readonly property string currentCollectionId:
        currentFilterKey.indexOf("collection:") === 0
        ? currentFilterKey.substring("collection:".length) : ""
    readonly property string currentShelfLabel: {
        library.collection_revision
        if (currentCollectionId.length > 0) {
            const index = collectionIndexForId(currentCollectionId)
            if (index >= 0)
                return library.collection_name_at(index).toUpperCase()
        }
        if (currentPlatformName.length > 0)
            return currentPlatformName.toUpperCase()
        for (let index = 0; index < categories.length; ++index) {
            if (categories[index].key === currentFilterKey)
                return categories[index].label
        }
        return "ALL GAMES"
    }
    readonly property url heroUrl: {
        mediaRevision
        return active && heroMediaId > 0
               ? library.artwork_url(heroMediaId, "fanart") : ""
    }
    readonly property url coverUrl: {
        mediaRevision
        return selectedMediaId > 0
               ? library.artwork_url(selectedMediaId, "box-front") : ""
    }
    readonly property bool favorite: {
        library.favorite_revision
        return selectedGameId.length > 0 && library.is_favorite(selectedGameId)
    }
    readonly property bool favoriteBusy: {
        library.favorite_pending_count
        return selectedGameId.length > 0 && library.favorite_pending(selectedGameId)
    }
    readonly property bool detailsCurrent: selectedGameId.length > 0
                                           && details.game_id === selectedGameId
    readonly property int downloadJobIndex: {
        downloadQueue.revision
        return selectedGameId.length > 0
                ? downloadQueue.job_index_for_game(selectedGameId) : -1
    }
    readonly property string downloadJobState: downloadJobIndex >= 0
                                                  ? downloadQueue.job_state_at(downloadJobIndex)
                                                  : ""
    readonly property bool downloadInProgress: downloadJobIndex >= 0
                                               && downloadJobState !== "IMPORTED"
    readonly property string primaryAction: details.game_running
            ? details.session_stopping ? "Stopping…" : "Stop emulator"
            : details.launch_busy ? "Cancel preparation"
            : !detailsCurrent ? selectedLocal ? "Play" : selectedDownloadable ? "Download options" : "View details"
            : details.loading ? "Loading…"
            : details.download_busy ? "Adding download…"
            : details.can_launch ? "Play"
            : selectedLocal ? "Set up play"
            : downloadInProgress ? "View download"
            : selectedDownloadable ? "Download options"
            : "View details"

    CouchPrimaryAction {
        id: detailsPrimary
        details: view.details
        current: view.detailsCurrent
        local: view.detailsCurrent ? view.details.local : view.selectedLocal
        downloadable: view.detailsCurrent ? view.details.downloadable : view.selectedDownloadable
        downloadState: view.downloadJobState
        downloadProgress: {
            view.downloadQueue.revision
            return view.downloadJobIndex >= 0 ? view.downloadQueue.job_progress_at(view.downloadJobIndex) : 0
        }
        onRequested: function(kind) {
            if (kind === "install") view.openDownloadOverlay()
            else if (kind === "download") view.downloadsRequested()
            else if (kind === "setup") view.manageGameRequested("launch")
            else if (kind === "files") view.manageGameRequested("files")
            else {
                view.closeOverlay()
                view.activateAction(0)
            }
        }
    }

    signal exitRequested()
    signal filterRequested(string key)
    signal platformRequested(string platform)
    signal collectionRequested(string collectionId, string collectionName)
    signal variantRequested(string gameId, int databaseId, string title,
                            string platform, bool local, bool downloadable)
    signal gameSelected(string gameId, int databaseId, string title,
                        string platform, bool local, bool downloadable)
    signal detailsRequested(string gameId, int databaseId, string title,
                            string platform, bool local, bool downloadable)
    signal settingsRequested(string section)
    signal toolsRequested()
    signal launchRequested()
    signal downloadsRequested()
    signal manageGameRequested(string section)
    signal torrentImportRequested(string gameId, int databaseId, string title,
                                  string platform)

    visible: active
    focus: active
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    CouchFeedback {
        id: feedback
        active: view.active && view.inputEnabled
        muted: !view.sfxEnabled || view.audioSuppressedForVoice
        volume: view.sfxVolume
    }

    function openSearch(initialText, microphone) {
        if (!active || !inputEnabled) return
        stopAttractMode()
        overlayOpen = false
        platformWheelOpen = false
        collectionWheelOpen = false
        variantWheelOpen = false
        searchOpen = true
        searchOverlay.open(initialText)
        if (!searchOverlay.askMode && initialText !== searchText) searchRequested(initialText)
        if (microphone) searchOverlay.microphone()
        else feedback.play("confirm")
        noteActivity()
    }

    function closeSearch() {
        searchOverlay.cancelVoice()
        searchOpen = false
        navigationZone = 2
        if (active && inputEnabled) forceActiveFocus()
        noteActivity()
    }

    MouseArea {
        anchors.fill: parent
        z: 99
        visible: view.searchOpen
        onClicked: view.closeSearch()
        onWheel: event => { event.accepted = true }
    }

    CouchSearchOverlay {
        id: searchOverlay
        z: 100
        anchors.horizontalCenter: parent.horizontalCenter
        y: 105
        width: Math.min(960, parent.width - 100)
        height: askMode ? Math.max(450, Math.min(800, view.height - 140)) : 335
        visible: view.searchOpen && view.active
        speech: view.speech
        assistant: view.assistant
        askMode: true
        conversationOnly: true
        microphoneController: view
        speechOutput: view.speechOutput
        query: view.searchText
        resultCount: shelf.count
        panelColor: view.panel
        inkColor: view.ink
        mutedColor: view.muted
        accentColor: view.accent
        onQueryEdited: text => view.searchRequested(text)
        onCloseRequested: view.closeSearch()
        onFeedbackRequested: kind => feedback.play(kind)
        onSettingsRequested: { view.closeSearch(); view.settingsRequested("local-ai") }
        onInstallationRequested: assistantModel => {
            if (assistantModel && view.conversationConfig.provider && view.conversationConfig.provider !== "builtin") {
                view.settingsRequested("local-ai")
                return
            }
            view.installAction = assistantModel ? "assistant" : "microphone"
            modelInstall.request(assistantModel, false)
        }
        onGameChosen: game => {
            view.selectedGameId = game.id
            view.selectedDatabaseId = game.database_id
            view.selectedTitle = game.title
            view.selectedPlatform = game.platform
            view.selectedLocal = game.local
            view.selectedDownloadable = game.downloadable
            view.selectedMediaId = view.library.media_id_for_game(game.id)
            view.requestDetails()
        }
    }

    Loader {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 85
        width: Math.min(1080, parent.width - 100)
        z: 98
        active: view.active && !!view.assistant && !!view.speechOutput
        sourceComponent: ConversationCaptions {
            width: parent.width
            assistant: view.assistant; speech: view.speech; speechOutput: view.speechOutput
            enabledCaptions: view.conversationConfig.captions !== false
            expanded: view.searchOpen
            inkColor: view.ink; accentColor: view.accent
            onConversationRequested: { searchOverlay.askMode = true; view.openSearch("", false) }
        }
    }

    onInputEnabledChanged: {
        if (!inputEnabled && searchOpen && !modelInstall.visible) closeSearch()
        else if (inputEnabled && active && searchOverlay.preservedRequest)
            Qt.callLater(function() {
                // Restoring focus synchronously would feed back into the
                // popupScope binding that determines inputEnabled.
                if (view.inputEnabled && view.active && !view.searchOpen && searchOverlay.preservedRequest)
                    view.openSearch(searchOverlay.preservedRequest, false)
            })
    }

    function accentFor(value) {
        const colors = [view.accent, view.accentCool,
                        Qt.lighter(view.accent, 1.22),
                        Qt.darker(view.accent, 1.28),
                        Qt.lighter(view.accentCool, 1.16),
                        Qt.darker(view.accentCool, 1.22)]
        if (!value || value.length === 0)
            return colors[0]
        return colors[value.charCodeAt(0) % colors.length]
    }

    function withAlpha(value, opacity) {
        return Qt.rgba(value.r, value.g, value.b, opacity)
    }

    function toggleViewStyle() {
        const selectedId = selectedGameId
        const selectedPlatformIndex = platformWheelIndex
        const nextStyle = viewStyles[(viewStyles.indexOf(library.couch_view_style) + 1) % viewStyles.length]
        if (!library.save_couch_view_style(nextStyle))
            return false
        feedback.play("switch")
        selectionReveal.restart()
        Qt.callLater(function() {
            if (platformWheelOpen) {
                platformWheel.currentIndex = selectedPlatformIndex
                platformWheel.positionViewAtIndex(selectedPlatformIndex, ListView.Contain)
            }
            if (selectedId.length > 0)
                focusGameById(selectedId)
            else if (shelf.currentIndex >= 0)
                shelf.positionViewAtIndex(shelf.currentIndex, ListView.Center)
            forceActiveFocus()
        })
        return true
    }

    function moveShelf(delta) {
        if (shelf.count <= 0)
            return
        noteActivity()
        const previous = shelf.currentIndex
        shelf.currentIndex = cinematicWheel
            ? ((shelf.currentIndex + delta) % shelf.count + shelf.count) % shelf.count
            : Math.max(0, Math.min(shelf.count - 1, shelf.currentIndex + delta))
        if (previous !== shelf.currentIndex) feedback.play(view.movementCue)
        shelf.positionViewAtIndex(shelf.currentIndex, ListView.Contain)
    }

    function noteActivity() {
        if (attractIdleTimer.running)
            attractIdleTimer.restart()
    }

    function startAttractMode(reason) {
        if (!active || shelf.count <= 0)
            return false
        overlayOpen = false
        platformWheelOpen = false
        collectionWheelOpen = false
        variantWheelOpen = false
        attractReason = reason === "idle" ? "idle" : "manual"
        navigationZone = 2
        if (shelf.currentIndex < 0)
            shelf.currentIndex = 0
        shelf.positionViewAtIndex(shelf.currentIndex, ListView.Center)
        captureCurrentGame()
        loadCurrentGame()
        attractOpen = true
        attractCycleTimer.restart()
        attractProgressAnimation.restart()
        forceActiveFocus()
        return true
    }

    function stopAttractMode() {
        if (!attractOpen)
            return
        attractOpen = false
        attractProgressAnimation.stop()
        if (active) {
            forceActiveFocus()
            noteActivity()
        }
    }

    function moveAttract(delta) {
        if (shelf.count <= 0)
            return
        const current = Math.max(0, shelf.currentIndex)
        shelf.currentIndex = ((current + delta) % shelf.count + shelf.count) % shelf.count
        shelf.positionViewAtIndex(shelf.currentIndex, ListView.Center)
        selectionDelay.restart()
        attractCycleTimer.restart()
        attractProgressAnimation.restart()
    }

    function chooseCategory(index) {
        entrySelection.cancel()
        feedback.play("confirm")
        noteActivity()
        categoryIndex = Math.max(0, Math.min(categories.length - 1, index))
        if (categories[categoryIndex].key === "platform") {
            openPlatformWheel()
            return
        }
        if (categories[categoryIndex].key === "collections") {
            openCollectionWheel()
            return
        }
        const shelfKey = categories[categoryIndex].key.length > 0
                         ? categories[categoryIndex].key : "all"
        library.save_couch_state(shelfKey, "")
        filterRequested(categories[categoryIndex].key)
        shelf.currentIndex = 0
    }

    function syncCategory() {
        if (currentCollectionId.length > 0) {
            for (let collectionCategory = 0;
                    collectionCategory < categories.length;
                    ++collectionCategory) {
                if (categories[collectionCategory].key === "collections") {
                    categoryIndex = collectionCategory
                    return
                }
            }
        }
        if (currentPlatformName.length > 0) {
            for (let platformIndex = 0; platformIndex < categories.length;
                    ++platformIndex) {
                if (categories[platformIndex].key === "platform") {
                    categoryIndex = platformIndex
                    return
                }
            }
        }
        for (let index = 0; index < categories.length; ++index) {
            if (categories[index].key === currentFilterKey) {
                categoryIndex = index
                return
            }
        }
        categoryIndex = 0
    }

    function platformIndexForName(name) {
        if (!name || name.length === 0)
            return 0
        for (let index = 0; index < library.platform_count; ++index) {
            if (library.platform_name_at(index) === name)
                return index
        }
        return 0
    }

    function openPlatformWheel() {
        if (library.platform_count <= 0)
            return
        overlayOpen = false
        collectionWheelOpen = false
        variantWheelOpen = false
        attractOpen = false
        platformWheelIndex = platformIndexForName(currentPlatformName)
        platformWheel.currentIndex = platformWheelIndex
        platformWheel.positionViewAtIndex(platformWheelIndex, ListView.Center)
        platformWheelOpen = true
        forceActiveFocus()
    }

    function focusPlatform(name) {
        if (!platformWheelOpen)
            openPlatformWheel()
        platformWheelIndex = platformIndexForName(name)
        platformWheel.currentIndex = platformWheelIndex
        platformWheel.positionViewAtIndex(platformWheelIndex, ListView.Center)
    }

    function closePlatformWheel() {
        if (platformWheelOpen) feedback.play("back")
        platformWheelOpen = false
        if (active)
            forceActiveFocus()
    }

    function movePlatformWheel(delta) {
        if (library.platform_count <= 0)
            return
        platformWheelIndex = cinematicWheel
            ? ((platformWheelIndex + delta) % library.platform_count + library.platform_count) % library.platform_count
            : Math.max(0, Math.min(library.platform_count - 1, platformWheelIndex + delta))
        platformWheel.currentIndex = platformWheelIndex
        platformWheel.positionViewAtIndex(platformWheelIndex, ListView.Contain)
    }

    function choosePlatform(index) {
        entrySelection.cancel()
        feedback.play("confirm")
        noteActivity()
        const platform = library.platform_name_at(index)
        if (platform.length === 0
                || !library.save_couch_state("platform", platform))
            return
        platformWheelIndex = index
        platformWheelOpen = false
        navigationZone = 2
        platformRequested(platform)
        forceActiveFocus()
    }

    function collectionIndexForId(collectionId) {
        for (let index = 0; index < library.collection_count; ++index) {
            if (library.collection_id_at(index) === collectionId)
                return index
        }
        return -1
    }

    function openCollectionWheel() {
        overlayOpen = false
        platformWheelOpen = false
        variantWheelOpen = false
        attractOpen = false
        const selectedIndex = collectionIndexForId(currentCollectionId)
        collectionWheelIndex = selectedIndex >= 0 ? selectedIndex : 0
        collectionWheel.currentIndex = library.collection_count > 0
                                     ? collectionWheelIndex : -1
        if (collectionWheel.currentIndex >= 0)
            collectionWheel.positionViewAtIndex(collectionWheel.currentIndex,
                                                ListView.Center)
        collectionWheelOpen = true
        forceActiveFocus()
    }

    function focusCollection(collectionId) {
        if (!collectionWheelOpen)
            openCollectionWheel()
        const index = collectionIndexForId(collectionId)
        if (index < 0)
            return false
        collectionWheelIndex = index
        collectionWheel.currentIndex = index
        collectionWheel.positionViewAtIndex(index, ListView.Center)
        return true
    }

    function closeCollectionWheel() {
        if (collectionWheelOpen) feedback.play("back")
        collectionWheelOpen = false
        if (active)
            forceActiveFocus()
    }

    function currentVariantIndex() {
        for (let index = 0; index < view.details.variant_count; ++index) {
            if (view.details.variant_is_current_at(index))
                return index
        }
        return 0
    }

    function openVariantWheel() {
        if (view.details.loading || view.details.variant_count < 2)
            return false
        overlayOpen = false
        platformWheelOpen = false
        collectionWheelOpen = false
        attractOpen = false
        variantWheelIndex = currentVariantIndex()
        variantWheel.currentIndex = variantWheelIndex
        variantWheel.positionViewAtIndex(variantWheelIndex, ListView.Center)
        variantWheelOpen = true
        forceActiveFocus()
        return true
    }

    function closeVariantWheel() {
        if (variantWheelOpen) feedback.play("back")
        variantWheelOpen = false
        if (active) {
            overlayMode = "menu"
            overlayOpen = true
            menuActionIndex = 3
            forceActiveFocus()
        }
    }

    function moveVariantWheel(delta) {
        if (view.details.variant_count <= 0)
            return
        variantWheelIndex = Math.max(0, Math.min(view.details.variant_count - 1,
                                                  variantWheelIndex + delta))
        variantWheel.currentIndex = variantWheelIndex
        variantWheel.positionViewAtIndex(variantWheelIndex, ListView.Center)
    }

    function focusVariant(index) {
        if (index < 0 || index >= view.details.variant_count)
            return false
        variantWheelIndex = index
        variantWheel.currentIndex = index
        variantWheel.positionViewAtIndex(index, ListView.Center)
        return true
    }

    function chooseVariant(index) {
        if (index < 0 || index >= view.details.variant_count
                || view.details.variant_is_current_at(index))
            return false
        const gameId = view.details.variant_game_id_at(index)
        const databaseId = view.details.variant_database_id_at(index)
        const title = view.details.variant_title_at(index)
        const platform = view.selectedPlatform
        const local = view.details.variant_is_local_at(index)
        const downloadable = view.details.variant_is_downloadable_at(index)
        if (gameId.length === 0 || title.length === 0)
            return false
        variantWheelOpen = false
        navigationZone = 2
        selectedGameId = gameId
        selectedDatabaseId = databaseId
        selectedMediaId = library.media_id_for_game(gameId)
        selectedTitle = title
        selectedLocal = local
        selectedDownloadable = downloadable
        loadedGameId = ""
        library.request_priority_artwork(selectedMediaId, title, platform, "box-front")
        library.request_priority_artwork(selectedMediaId, title, platform, "fanart")
        variantRequested(gameId, databaseId, title, platform, local, downloadable)
        focusGameById(gameId)
        forceActiveFocus()
        return true
    }

    function focusGameById(gameId) {
        const row = library.row_for_game(gameId)
        if (row < 0 || row >= shelf.count)
            return false
        shelf.currentIndex = row
        shelf.positionViewAtIndex(row, ListView.Center)
        return true
    }

    function openRelatedGame(index) {
        // Related records may be outside the current shelf/filter. Keep their
        // identity explicit instead of reopening the highlighted shelf card.
        const gameId = details.related_game_id_at(index)
        if (!gameId) return false
        selectedDatabaseId = details.related_game_database_id_at(index)
        selectedTitle = details.related_game_title_at(index)
        selectedPlatform = details.related_game_platform_at(index)
        selectedLocal = details.related_game_is_local_at(index)
        selectedDownloadable = details.related_game_is_downloadable_at(index)
        selectedGameId = gameId
        selectedMediaId = library.media_id_for_game(gameId)
        heroMediaId = selectedMediaId
        library.request_couch_preview(gameId)
        requestDetails()
        return true
    }

    function moveCollectionWheel(delta) {
        if (library.collection_count <= 0)
            return
        collectionWheelIndex = Math.max(
                    0, Math.min(library.collection_count - 1,
                                collectionWheelIndex + delta))
        collectionWheel.currentIndex = collectionWheelIndex
        collectionWheel.positionViewAtIndex(collectionWheelIndex,
                                            ListView.Center)
    }

    function chooseCollection(index) {
        feedback.play("confirm")
        noteActivity()
        const collectionId = library.collection_id_at(index)
        const collectionName = library.collection_name_at(index)
        if (collectionId.length === 0
                || !library.save_couch_state("collection:" + collectionId, ""))
            return
        collectionWheelIndex = index
        collectionWheelOpen = false
        navigationZone = 2
        collectionRequested(collectionId, collectionName)
        forceActiveFocus()
    }

    function captureCurrentGame() {
        if (entrySelection.pending || library.filtering) return false
        if (overlayOpen) return true
        const item = shelf.currentItem
        if (!item) {
            selectionRetry.restart()
            return false
        }
        // Installation can change without changing the selected catalog row.
        selectedLocal = item.gameLocal
        selectedDownloadable = item.gameDownloadable
        selectedGameId = item.gameId
        selectedDatabaseId = item.gameDatabaseId
        selectedMediaId = item.gameMediaId
        selectedTitle = item.gameTitle
        selectedPlatform = item.gamePlatform
        return true
    }

    function loadCurrentGame() {
        if (!captureCurrentGame() || loadedGameId === selectedGameId)
            return
        loadedGameId = selectedGameId
        heroMediaId = selectedMediaId
        library.request_couch_preview(selectedGameId)
        library.request_priority_artwork_for_game(selectedGameId, "fanart")
        library.request_priority_artwork_for_game(selectedGameId, "box-front")
        if (cinematicWheel)
            library.request_priority_artwork_for_game(selectedGameId, "clear-logo")
        gameSelected(selectedGameId, selectedDatabaseId, selectedTitle,
                     selectedPlatform, selectedLocal, selectedDownloadable)
    }

    function requestDetails() {
        if (selectedGameId.length === 0)
            return
        detailsRequested(selectedGameId, selectedDatabaseId, selectedTitle,
                         selectedPlatform, selectedLocal, selectedDownloadable)
        openOverlay("details")
    }

    function openDownloadOverlay() {
        if (!detailsCurrent || details.loading || !details.downloadable)
            return
        attractOpen = false
        platformWheelOpen = false
        collectionWheelOpen = false
        variantWheelOpen = false
        overlayOpen = false
        downloadOverlayOpen = true
        downloadScreen.resetForGame()
        forceActiveFocus()
    }

    function closeDownloadOverlay() {
        downloadOverlayOpen = false
        if (active)
            forceActiveFocus()
    }

    function activateAction(index) {
        feedback.play("confirm")
        if (index === 0 && details.game_running) {
            details.stop_emulator()
            return
        }
        if (index === 0 && details.launch_busy) {
            details.cancel_launch()
            return
        }
        if (selectedGameId.length === 0)
            return
        if (index === 0) {
            if (!detailsCurrent) {
                if (selectedLocal) {
                    feedback.play("launch")
                    launchStatusOverlayOpen = true
                    launchRequested()
                } else requestDetails()
                return
            }
            if (details.loading)
                return
            if (details.can_launch && !details.launch_busy
                    && !details.game_running) {
                feedback.play("launch")
                launchStatusOverlayOpen = true
                launchRequested()
            } else if (downloadInProgress) {
                downloadsRequested()
            } else if (selectedDownloadable) {
                openDownloadOverlay()
            } else {
                requestDetails()
            }
        } else if (index === 1) {
            requestDetails()
        } else if (!favoriteBusy) {
            library.set_favorite(selectedGameId, !favorite)
        }
    }

    function openOverlay(mode) {
        feedback.play("confirm")
        if (!detailsCurrent && selectedGameId.length > 0)
            detailsRequested(selectedGameId, selectedDatabaseId, selectedTitle,
                             selectedPlatform, selectedLocal, selectedDownloadable)
        attractOpen = false
        platformWheelOpen = false
        collectionWheelOpen = false
        variantWheelOpen = false
        overlayMode = mode === "menu" ? "menu" : "details"
        overlayOpen = true
        menuActionIndex = 0
        detailsScroller.contentY = 0
        if (nativeDetails.item) nativeDetails.item.reset()
        forceActiveFocus()
    }

    function closeOverlay() {
        feedback.play("back")
        overlayOpen = false
        loadedGameId = ""
        loadCurrentGame()
        if (active)
            forceActiveFocus()
    }

    function captureOverlay(path, callback) {
        couchOverlay.grabToImage(function(result) {
            callback(result.saveToFile(path))
        })
    }

    function captureTheme(path, callback) {
        view.grabToImage(function(result) {
            callback(result.saveToFile(path))
        })
    }

    function capturePlatformWheel(path, callback) {
        platformWheelOverlay.grabToImage(function(result) {
            callback(result.saveToFile(path))
        })
    }

    function captureCollectionWheel(path, callback) {
        collectionWheelOverlay.grabToImage(function(result) {
            callback(result.saveToFile(path))
        })
    }

    function captureVariantWheel(path, callback) {
        variantWheelOverlay.grabToImage(function(result) {
            callback(result.saveToFile(path))
        })
    }

    function captureAttract(path, callback) {
        attractOverlay.grabToImage(function(result) {
            callback(result.saveToFile(path))
        })
    }

    function captureLaunchStatus(path, callback) {
        launchStatusOverlay.capture(path, callback)
    }

    function captureDownload(path, callback) {
        downloadScreen.grabToImage(function(result) {
            callback(result.saveToFile(path))
        })
    }

    function closeLaunchStatus() {
        launchCompletionPending = false
        launchStatusOverlayOpen = false
        forceActiveFocus()
    }

    function menuActionLabel(index) {
        if (index === 8) return "Search games · voice or keyboard"
        if (index === 0)
            return primaryAction
        if (index === 1)
            return favorite ? "Remove favorite" : "Add favorite"
        if (index === 2)
            return "Game details & tools"
        if (index === 3)
            return "Releases & media"
        if (index === 4)
            return "Start attract mode"
        if (index === 5)
            return "Change view · " + viewLabel
        if (index === 6)
            return library.couch_music_enabled
                   ? "Mute background music" : "Enable background music"
        return "Library & settings"
    }

    function menuActionDescription(index) {
        if (index === 8) return "Search this shelf without leaving Couch Mode. Speak a title or type it."
        if (index === 0) {
            if (details.can_launch)
                return "Launch with the selected emulator and exact local file."
            if (downloadInProgress)
                return "Open the exact ROM download, import status, and recovery controls."
            if (selectedDownloadable)
                return "Review exact Minerva files and download options."
            if (selectedLocal)
                return "Choose an installed emulator and finish play setup."
            return "Open the complete management view for this catalog record."
        }
        if (index === 1)
            return favorite ? "Remove this exact game from Favorites."
                            : "Keep this exact game in Favorites."
        if (index === 2)
            return "All game information, patches, cheats, achievements, saves, controllers, display and launch settings."
        if (index === 3)
            return "Browse exact regional and version releases before choosing one."
        if (index === 4)
            return "Let Couch Mode rotate through games on the current shelf."
        if (index === 5)
            return "Cycle animated wheel, classic shelf, cover wall and album views."
        if (index === 6)
            return library.couch_music_enabled
                   ? "Stop automatic cached game music throughout Couch Mode."
                   : "Automatically play cached game music after selection settles."
        return "Search, downloads, notifications, imports, collections and every setting."
    }

    function menuActionEnabled(index) {
        return index !== 3 || (!view.details.loading && view.details.variant_count > 1)
    }

    function nextMenuAction(start, delta) {
        let index = start
        for (let step = 0; step < menuActionCount; ++step) {
            index = Math.max(0, Math.min(menuActionCount - 1, index + delta))
            if (menuActionEnabled(index))
                return index
            if (index === 0 || index === menuActionCount - 1)
                break
        }
        return start
    }

    function activateMenuAction(index) {
        if (index === 8) { openSearch(searchText, false); return }
        if (index === 0) {
            closeOverlay()
            activateAction(0)
        } else if (index === 1) {
            if (!favoriteBusy && selectedGameId.length > 0)
                library.set_favorite(selectedGameId, !favorite)
        } else if (index === 2) {
            closeOverlay()
            requestDetails()
        } else if (index === 3) {
            openVariantWheel()
        } else if (index === 4) {
            closeOverlay()
            startAttractMode("manual")
        } else if (index === 5) {
            closeOverlay()
            toggleViewStyle()
        } else if (index === 6) {
            library.save_couch_audio_settings(!library.couch_music_enabled,
                                              library.couch_music_volume)
        } else {
            closeOverlay()
            toolsRequested()
        }
    }

    function handleNavigation(action) {
        if (!active || !inputEnabled) return false
        shelf.cancelPointerSelection()
        platformWheel.cancelPointerSelection()
        if (searchOpen) return searchOverlay.handleNavigation(action)
        const handled = navigate(action)
        if (handled) feedback.play(action === "back" ? "back"
            : ["accept", "favorite", "details", "menu"].indexOf(action) >= 0 ? "confirm"
            : platformWheelOpen || navigationZone === 2 ? movementCue : "move")
        return handled
    }

    function navigate(action) {
        if (!active || !inputEnabled)
            return false
        // Desktop gives analog triggers Home/End; keep the established couch
        // paging shortcuts until this view's zone-specific navigation changes.
        if (action === "scroll_first") action = "page_left"
        if (action === "scroll_last") action = "page_right"
        forceActiveFocus()
        noteActivity()
        if (attractOpen) {
            if (action === "back") {
                stopAttractMode()
            } else if (action === "left" || action === "up") {
                moveAttract(-1)
            } else if (action === "right" || action === "down") {
                moveAttract(1)
            } else if (action === "page_left") {
                moveAttract(-5)
            } else if (action === "page_right") {
                moveAttract(5)
            } else if (action === "home") {
                shelf.currentIndex = 0
                shelf.positionViewAtBeginning()
                selectionDelay.restart()
                attractCycleTimer.restart()
                attractProgressAnimation.restart()
            } else if (action === "accept" || action === "menu") {
                stopAttractMode()
                openOverlay("menu")
            } else if (action === "details") {
                stopAttractMode()
                openOverlay("details")
            } else if (action === "favorite") {
                if (!favoriteBusy && selectedGameId.length > 0)
                    library.set_favorite(selectedGameId, !favorite)
            } else {
                return false
            }
            return true
        }
        if (launchStatusOverlayOpen) {
            if (action === "back") {
                closeLaunchStatus()
            } else if (action === "details") {
                launchCompletionPending = false
                launchStatusOverlayOpen = false
                requestDetails()
            } else if (action === "menu") {
                launchCompletionPending = false
                launchStatusOverlayOpen = false
                openOverlay("menu")
            } else if (action === "accept") {
                if (details.launch_busy)
                    details.cancel_launch()
                else
                    closeLaunchStatus()
            } else {
                return false
            }
            return true
        }
        if (downloadOverlayOpen)
            return downloadScreen.handleNavigation(action)
        if (platformWheelOpen) {
            if (action === "back") {
                closePlatformWheel()
            } else if (action === "details") {
                systemMediaRequested(library.platform_name_at(platformWheelIndex))
            } else if (action === "menu" || action === "cycle_zone") {
                toggleViewStyle()
            } else if (action === "up") {
                movePlatformWheel(-platformWheel.columns)
            } else if (action === "down") {
                movePlatformWheel(platformWheel.columns)
            } else if (action === "left") {
                movePlatformWheel(-1)
            } else if (action === "right") {
                movePlatformWheel(1)
            } else if (action === "page_left") {
                movePlatformWheel(-5)
            } else if (action === "page_right") {
                movePlatformWheel(5)
            } else if (action === "home") {
                platformWheelIndex = 0
                platformWheel.currentIndex = 0
                platformWheel.positionViewAtBeginning()
            } else if (action === "accept") {
                choosePlatform(platformWheelIndex)
            } else {
                return false
            }
            return true
        }
        if (variantWheelOpen) {
            if (action === "back") {
                closeVariantWheel()
            } else if (action === "up" || action === "left") {
                moveVariantWheel(-1)
            } else if (action === "down" || action === "right") {
                moveVariantWheel(1)
            } else if (action === "page_left") {
                moveVariantWheel(-5)
            } else if (action === "page_right") {
                moveVariantWheel(5)
            } else if (action === "home") {
                variantWheelIndex = 0
                variantWheel.currentIndex = 0
                variantWheel.positionViewAtBeginning()
            } else if (action === "accept") {
                chooseVariant(variantWheelIndex)
            } else {
                return false
            }
            return true
        }
        if (collectionWheelOpen) {
            if (action === "back") {
                closeCollectionWheel()
            } else if (action === "up" || action === "left") {
                moveCollectionWheel(-1)
            } else if (action === "down" || action === "right") {
                moveCollectionWheel(1)
            } else if (action === "page_left") {
                moveCollectionWheel(-5)
            } else if (action === "page_right") {
                moveCollectionWheel(5)
            } else if (action === "home") {
                collectionWheelIndex = 0
                collectionWheel.currentIndex = library.collection_count > 0 ? 0 : -1
                if (collectionWheel.currentIndex >= 0)
                    collectionWheel.positionViewAtBeginning()
            } else if (action === "accept" && library.collection_count > 0) {
                chooseCollection(collectionWheelIndex)
            } else {
                return false
            }
            return true
        }
        if (overlayOpen) {
            if (overlayMode === "details" && nativeDetails.item)
                return nativeDetails.item.handleNavigation(action)
            if (action === "back") {
                closeOverlay()
            } else if (action === "details" || action === "page_left"
                       || action === "left") {
                overlayMode = "details"
                detailsScroller.contentY = 0
            } else if (action === "menu" || action === "page_right"
                       || action === "right") {
                overlayMode = "menu"
            } else if (action === "up") {
                if (overlayMode === "menu")
                    menuActionIndex = nextMenuAction(menuActionIndex, -1)
                else
                    detailsScroller.contentY = Math.max(0,
                                                        detailsScroller.contentY - 90)
            } else if (action === "down") {
                if (overlayMode === "menu")
                    menuActionIndex = nextMenuAction(menuActionIndex, 1)
                else
                    detailsScroller.contentY = Math.min(
                                Math.max(0, detailsScroller.contentHeight
                                         - detailsScroller.height),
                                detailsScroller.contentY + 90)
            } else if (action === "home") {
                if (overlayMode === "menu")
                    menuActionIndex = 0
                else
                    detailsScroller.contentY = 0
            } else if (action === "favorite") {
                if (!favoriteBusy && selectedGameId.length > 0)
                    library.set_favorite(selectedGameId, !favorite)
            } else if (action === "accept") {
                if (overlayMode === "menu")
                    activateMenuAction(menuActionIndex)
                else
                    overlayMode = "menu"
            } else {
                return false
            }
            return true
        }
        if (action === "back") {
            if (searchText.length > 0) searchRequested("")
            else exitRequested()
        } else if (action === "up") {
            if (wallView && navigationZone === 2 && shelf.currentIndex >= shelf.columns)
                moveShelf(-shelf.columns)
            else if (cinematicWheel && navigationZone === 2)
                moveShelf(-1)
            else
                navigationZone = Math.max(0, navigationZone - 1)
        } else if (action === "down") {
            if (wallView && navigationZone === 2)
                moveShelf(shelf.columns)
            else if (cinematicWheel && navigationZone === 2)
                moveShelf(1)
            else
                navigationZone = Math.min(2, navigationZone + 1)
        } else if (action === "left") {
            if (navigationZone === 0)
                categoryIndex = Math.max(0, categoryIndex - 1)
            else if (navigationZone === 1)
                actionIndex = Math.max(0, actionIndex - 1)
            else if (cinematicWheel)
                navigationZone = 1
            else
                moveShelf(-1)
        } else if (action === "right") {
            if (navigationZone === 0)
                categoryIndex = Math.min(categories.length - 1,
                                         categoryIndex + 1)
            else if (navigationZone === 1) {
                if (cinematicWheel && actionIndex >= 2)
                    navigationZone = 2
                else
                    actionIndex = Math.min(2, actionIndex + 1)
            } else if (!cinematicWheel) {
                moveShelf(1)
            }
        } else if (action === "page_left") {
            navigationZone = 2
            moveShelf(-5)
        } else if (action === "page_right") {
            navigationZone = 2
            moveShelf(5)
        } else if (action === "home") {
            navigationZone = 2
            shelf.currentIndex = shelf.count > 0 ? 0 : -1
        } else if (action === "accept") {
            if (navigationZone === 0)
                chooseCategory(categoryIndex)
            else if (navigationZone === 1)
                activateAction(actionIndex)
            else
                activateAction(0)
        } else if (action === "favorite") {
            if (!favoriteBusy && selectedGameId.length > 0)
                library.set_favorite(selectedGameId, !favorite)
        } else if (action === "details") {
            openOverlay("details")
        } else if (action === "menu") {
            openOverlay("menu")
        } else if (action === "cycle_zone") {
            navigationZone = (navigationZone + 1) % 3
        } else {
            return false
        }
        return true
    }

    onActiveChanged: {
        if (active) {
            entrySound.restart()
            overlayOpen = false
            platformWheelOpen = false
            collectionWheelOpen = false
            variantWheelOpen = false
            attractOpen = false
            downloadOverlayOpen = false
            launchStatusOverlayOpen = details.game_running || details.launch_busy
                                      || launchCompletionPending
            if (details.game_running)
                launchSessionObserved = true
            forceActiveFocus()
            syncCategory()
            const preferredRow = library.row_for_game(preferredGameId)
            if (preferredRow >= 0)
                shelf.currentIndex = preferredRow
            else if (shelf.currentIndex < 0 && shelf.count > 0)
                shelf.currentIndex = 0
            if (shelf.currentIndex >= 0)
                shelf.positionViewAtIndex(shelf.currentIndex, ListView.Center)
            selectionDelay.restart()
        } else {
            handsFreeSetup.cancel()
            entrySelection.cancel()
            closeSearch()
            overlayOpen = false
            platformWheelOpen = false
            collectionWheelOpen = false
            variantWheelOpen = false
            attractOpen = false
            downloadOverlayOpen = false
            launchStatusOverlayOpen = false
        }
    }

    onSelectedGameIdChanged: {
        if (active && selectedGameId) selectionReveal.restart()
        if (selectedGameId.length === 0 || !detailsCurrent) {
            downloadOverlayOpen = false
            launchStatusOverlayOpen = false
            launchSessionObserved = false
            launchCompletionPending = false
        }
    }

    Connections {
        target: view.details
        function onLaunch_busyChanged() {
            if (view.details.launch_busy) {
                view.launchSessionObserved = false
                view.launchCompletionPending = false
                view.launchStatusOverlayOpen = true
            }
        }
        function onGame_runningChanged() {
            if (view.details.game_running) {
                view.launchSessionObserved = true
                view.launchCompletionPending = false
                view.launchStatusOverlayOpen = true
            } else if (view.launchSessionObserved) {
                view.launchSessionObserved = false
                view.launchCompletionPending = true
                if (view.active) {
                    view.launchStatusOverlayOpen = true
                    view.forceActiveFocus()
                }
            }
        }
        function onLaunch_statusChanged() {
            if (!view.details.launch_busy && !view.details.game_running
                    && view.details.launch_status.indexOf("Could not launch") === 0) {
                view.launchCompletionPending = true
                if (view.active)
                    view.launchStatusOverlayOpen = true
            }
        }
    }

    onCurrentFilterKeyChanged: syncCategory()
    onCurrentPlatformNameChanged: syncCategory()

    Keys.onPressed: event => handleKey(event)

    function handleKey(event) {
        if (!inputEnabled) return
        if (!active)
            return
        if (searchOpen) return
        const shortcut = (event.modifiers & Qt.ControlModifier) !== 0
        if (event.key === Qt.Key_F3 || event.key === Qt.Key_F2) {
            openSearch(searchText, event.key === Qt.Key_F2)
            event.accepted = true
            return
        }
        if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                // Qt's JS engine does not implement Unicode property escapes.
                && /^[a-z0-9]/i.test(event.text)
                && !overlayOpen && !downloadOverlayOpen
                && !launchStatusOverlayOpen) {
            openSearch(event.text, false)
            event.accepted = true
            return
        }
        let action = ""
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            action = "back"
        } else if (event.key === Qt.Key_Up) {
            action = "up"
        } else if (event.key === Qt.Key_Down) {
            action = "down"
        } else if (event.key === Qt.Key_Left) {
            action = "left"
        } else if (event.key === Qt.Key_Right) {
            action = "right"
        } else if (event.key === Qt.Key_PageUp) {
            action = "page_left"
        } else if (event.key === Qt.Key_PageDown) {
            action = "page_right"
        } else if (event.key === Qt.Key_Home) {
            action = "home"
        } else if (event.key === Qt.Key_End) {
            if (attractOpen) {
                shelf.currentIndex = Math.max(0, shelf.count - 1)
                shelf.positionViewAtEnd()
                selectionDelay.restart()
                attractCycleTimer.restart()
                attractProgressAnimation.restart()
            } else if (platformWheelOpen) {
                platformWheelIndex = Math.max(0, library.platform_count - 1)
                platformWheel.currentIndex = platformWheelIndex
                platformWheel.positionViewAtEnd()
            } else if (collectionWheelOpen) {
                collectionWheelIndex = Math.max(0, library.collection_count - 1)
                collectionWheel.currentIndex = collectionWheelIndex
                if (collectionWheel.currentIndex >= 0)
                    collectionWheel.positionViewAtEnd()
            } else if (variantWheelOpen) {
                variantWheelIndex = Math.max(0, view.details.variant_count - 1)
                variantWheel.currentIndex = variantWheelIndex
                variantWheel.positionViewAtEnd()
            } else {
                navigationZone = 2
                shelf.currentIndex = shelf.count - 1
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            action = "accept"
        } else if (event.key === Qt.Key_F && shortcut && !favoriteBusy) {
            action = "favorite"
        } else if (event.key === Qt.Key_D && shortcut) {
            action = "details"
        } else if (event.key === Qt.Key_M && shortcut) {
            action = "menu"
        } else if (event.key === Qt.Key_O && shortcut) {
            toolsRequested()
            event.accepted = true
            return
        } else if (event.key === Qt.Key_A && shortcut) {
            if (attractOpen)
                action = "back"
            else {
                event.accepted = startAttractMode("manual")
                return
            }
        } else if (event.key === Qt.Key_V && shortcut
                   && !overlayOpen && !attractOpen
                   && !collectionWheelOpen
                   && !variantWheelOpen && !launchStatusOverlayOpen) {
            event.accepted = toggleViewStyle()
            return
        } else if (event.key === Qt.Key_P && shortcut
                   && couchMusic.visible
                   && !overlayOpen && !platformWheelOpen
                   && !collectionWheelOpen && !variantWheelOpen
                   && !launchStatusOverlayOpen) {
            couchMusic.togglePlayback()
            event.accepted = true
            return
        } else if (event.key === Qt.Key_Tab) {
            action = "cycle_zone"
        }
        if (action.length > 0)
            event.accepted = handleNavigation(action)
    }

    Rectangle {
        anchors.fill: parent
        color: view.background
    }

    Image {
        id: themeBackgroundImage
        anchors.fill: parent
        source: view.active ? view.library.couch_theme_background_image : ""
        asynchronous: true
        cache: true
        autoTransform: true
        fillMode: Image.PreserveAspectCrop
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    Image {
        id: heroImage
        anchors.fill: parent
        source: view.heroUrl
        asynchronous: true
        cache: true
        autoTransform: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(1920, 1080)
        retainWhileLoading: true
        opacity: status === Image.Ready ? (view.cinematicWheel ? 1 : 0.78) : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    CouchVideoPreview {
        id: couchVideo
        objectName: "couchBackgroundVideo"
        anchors.fill: parent
        backgroundMode: true
        visible: view.hasPreviewVideo
        source: view.previewVideoUrl
        active: view.active && visible && view.inputEnabled && !view.overlayOpen
                && !view.platformWheelOpen && !view.collectionWheelOpen && !view.variantWheelOpen
                && !view.attractOpen && !view.launchStatusOverlayOpen && !view.downloadOverlayOpen
                && !view.details.game_running
        muted: view.videoMuted || view.audioSuppressedForVoice
        label: view.browsing.theme_video_url ? "HYPERSPIN VIDEO THEME" : "GAMEPLAY PREVIEW"
    }

    Rectangle {
        anchors.fill: parent
        visible: !view.wheelBrowseOnly
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: view.withAlpha(view.background, couchVideo.playing ? 0.88 : 0.96) }
            GradientStop { position: 0.38; color: view.withAlpha(view.background, couchVideo.playing ? 0.62 : 0.88) }
            GradientStop { position: 0.68; color: view.withAlpha(view.background, couchVideo.playing ? 0.12 : 0.3) }
            GradientStop { position: 1.0; color: view.withAlpha(view.background, couchVideo.playing ? 0.26 : 0.65) }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * (view.wheelBrowseOnly ? 0.20 : 0.43)
        gradient: Gradient {
            GradientStop { position: 0.0; color: view.withAlpha(view.background, 0) }
            GradientStop { position: 0.35; color: view.withAlpha(view.background, 0.72) }
            GradientStop { position: 1.0; color: view.background }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        visible: !view.wheelBrowseOnly
        height: 170
        gradient: Gradient {
            GradientStop { position: 0; color: view.withAlpha(view.background, 0.94) }
            GradientStop { position: 0.75; color: view.withAlpha(view.background, 0.7) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Row {
        id: brand
        visible: !view.wheelBrowseOnly
        anchors.left: parent.left
        anchors.leftMargin: 54
        anchors.top: parent.top
        anchors.topMargin: 34
        spacing: 13

        AppIcon {
            width: 40
            height: 40
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: -1
            Text {
                text: "LUNCHPAIL"
                color: view.ink
                font.pixelSize: 18
                font.weight: Font.Black
                font.letterSpacing: 1.8
            }
            Text {
                text: "COUCH MODE"
                color: view.muted
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 2.0
            }
        }
    }

    Row {
        id: categoryRow
        visible: !view.wheelBrowseOnly
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: brand.bottom
        anchors.topMargin: 18
        spacing: 12

        Repeater {
            model: view.categories
            delegate: Rectangle {
                id: categoryButton
                required property int index
                required property var modelData
                width: categoryLabel.implicitWidth + 28
                height: 36
                radius: Math.max(8, view.cardRadius - 6)
                color: view.categoryIndex === index
                       ? (view.navigationZone === 0 ? view.withAlpha(view.accent, 0.9)
                                                    : view.withAlpha(view.panelRaised, 0.78))
                       : categoryHover.hovered ? view.withAlpha(view.panelRaised, 0.58)
                                               : "transparent"
                border.color: view.categoryIndex === index
                              ? view.accent : "transparent"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 170 } }
                scale: categoryHover.hovered ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Rectangle {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 1 }
                    height: 2; radius: 1; width: parent.width * 0.55; color: view.accent
                    opacity: view.categoryIndex === categoryButton.index ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                Text {
                    id: categoryLabel
                    anchors.centerIn: parent
                    text: categoryButton.modelData.label
                    color: view.categoryIndex === categoryButton.index
                           && view.navigationZone === 0 ? view.background
                           : view.categoryIndex === categoryButton.index
                             ? view.ink : view.muted
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.letterSpacing: 0.8
                }
                HoverHandler { id: categoryHover; onHoveredChanged: if (hovered) feedback.play("focus") }
                TapHandler {
                    onTapped: {
                        view.navigationZone = 0
                        view.chooseCategory(categoryButton.index)
                        view.forceActiveFocus()
                    }
                }
            }
        }
    }

    Item {
        // Mouse users reveal the same navigation controls at the top edge;
        // controller/keyboard users reveal them by moving left to actions.
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 150
        z: 30
        HoverHandler { id: wheelToolbarHover; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad }
    }
    Row {
        id: headerActions
        visible: !view.wheelBrowseOnly
        z: 31
        anchors.right: parent.right
        anchors.rightMargin: 50
        anchors.verticalCenter: brand.verticalCenter
        spacing: 8

        CouchActionButton {
            id: searchButton
            soundFeedback: feedback; soundCue: ""
            text: "Assistant" + (view.speech.listening ? " · Listening" : view.microphoneEnabled ? " · Mic on" : " · F3")
            inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
            onClicked: view.openSearch("", false)
            ToolTip.visible: hovered
            ToolTip.text: "Type or talk to Lunchpail" + (view.microphoneEnabled ? " · Mic on" : " · Mic off")
            Accessible.name: "Open Lunchpail assistant"
        }
        CouchActionButton {
            text: view.viewLabel + "  ▾"
            soundFeedback: feedback; soundCue: ""
            inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
            onClicked: { view.noteActivity(); view.toggleViewStyle() }
            ToolTip.visible: hovered
            ToolTip.text: "Change view · Ctrl+V"
            Accessible.name: "Change Couch Mode view, " + view.viewLabel
        }
        CouchActionButton {
            text: "Library & settings"
            soundFeedback: feedback
            inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
            onClicked: view.toolsRequested()
        }
        CouchActionButton {
            width: 44; text: "×"
            soundFeedback: feedback; soundCue: "back"
            inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
            onClicked: view.exitRequested()
            Accessible.name: "Return to desktop mode"
        }
    }

    Rectangle {
        anchors.fill: gameCopy
        anchors.margins: -20
        visible: !view.cinematicWheel
        radius: 20
        color: view.withAlpha(view.panel, view.hasPreviewVideo ? 0.76 : 0.4)
        border.color: view.withAlpha(view.ink, 0.09)
        opacity: gameCopy.opacity
    }
    Rectangle {
        anchors { left: gameCopy.left; leftMargin: -22; top: gameCopy.top; topMargin: 4 }
        width: 3; height: Math.min(90, gameCopy.height); radius: 2
        color: view.accent
        visible: view.cinematicWheel && !view.wheelBrowseOnly
    }

    Column {
        id: gameCopy
        visible: !view.wheelBrowseOnly
        anchors.left: parent.left
        anchors.leftMargin: 70
        anchors.top: categoryRow.bottom
        anchors.topMargin: view.wallView || view.albumView ? 28 : Math.max(42, parent.height * 0.055)
        width: (view.wallView || view.albumView) && !view.hasPreviewVideo
               ? parent.width - 140 : Math.min(760, parent.width * 0.53 - 70)
        spacing: view.wallView || view.albumView ? 8 : 14
        transform: Translate { id: copyEntrance }

        Row {
            spacing: 9
            Rectangle {
                width: platformText.implicitWidth + 18
                height: 26
                radius: Math.max(6, view.cardRadius - 8)
                color: view.withAlpha(view.panelRaised, 0.72)
                border.color: view.withAlpha(view.muted, 0.48)
                Text {
                    id: platformText
                    anchors.centerIn: parent
                    text: view.selectedPlatform.length > 0
                          ? view.selectedPlatform.toUpperCase() : "CATALOG"
                    color: view.ink
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 0.8
                }
            }
            Rectangle {
                width: stateText.implicitWidth + 18
                height: 26
                radius: Math.max(6, view.cardRadius - 8)
                color: view.selectedLocal ? view.withAlpha(view.accentCool, 0.24)
                       : view.selectedDownloadable ? view.withAlpha(view.accent, 0.24)
                                                   : view.withAlpha(view.panelRaised, 0.72)
                border.color: view.selectedLocal ? view.accentCool
                              : view.selectedDownloadable ? view.accent
                                                          : view.withAlpha(view.muted, 0.48)
                Text {
                    id: stateText
                    anchors.centerIn: parent
                    text: view.selectedLocal ? "INSTALLED"
                          : view.selectedDownloadable ? "MINERVA" : "CATALOG"
                    color: view.selectedLocal ? view.accentCool
                           : view.selectedDownloadable ? view.accent : view.muted
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 0.9
                }
            }
        }

        Text {
            width: parent.width
            text: view.selectedTitle.length > 0 ? view.selectedTitle : "Choose a game"
            color: view.ink
            font.pixelSize: view.wallView || view.albumView ? 32 : Math.max(34, Math.min(56, view.width * 0.036))
            font.weight: Font.Bold
            lineHeight: 1.02
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Row {
            spacing: 18
            visible: !view.wallView && !view.albumView && view.selectedGameId.length > 0
            Text {
                visible: view.browsing.release_date.length > 0
                text: view.browsing.release_date
                color: view.muted
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                visible: view.browsing.genre.length > 0
                text: view.browsing.genre
                color: view.muted
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                visible: view.browsing.players.length > 0
                text: view.browsing.players + " players"
                color: view.muted
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                visible: view.browsing.cooperative === "yes"
                text: "CO-OP"
                color: view.accentCool
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                visible: view.browsing.rating.length > 0
                text: "★ " + view.browsing.rating
                color: view.accent
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Text {
            width: parent.width
            height: Math.min(implicitHeight, 112)
            visible: !view.wallView && !view.albumView && !(view.cinematicWheel && view.hasPreviewVideo)
            text: view.browsing.description
            color: view.withAlpha(view.ink, 0.86)
            font.pixelSize: 18
            lineHeight: 1.34
            wrapMode: Text.WordWrap
            maximumLineCount: 5
            elide: Text.ElideRight
        }

        Row {
            id: actionRow
            spacing: 10

            Repeater {
                model: 3
                delegate: Rectangle {
                    id: actionButton
                    required property int index
                    property bool selected: view.navigationZone === 1
                                            && view.actionIndex === index
                    readonly property bool playAction: index === 0
                                                       && view.primaryAction === "Play"
                    width: index === 0 ? 190 : index === 1 ? 185 : 52
                    height: 50
                    radius: Math.max(8, view.cardRadius - 4)
                    color: index === 0
                           ? (selected ? Qt.lighter(playAction ? view.playGreen : view.accent, 1.12)
                                       : view.withAlpha(playAction ? view.playGreen : view.accent, 0.9))
                           : selected ? view.withAlpha(view.muted, 0.82)
                                      : view.withAlpha(view.panelRaised, 0.76)
                    border.color: selected ? view.ink : index === 0
                                  ? (playAction ? view.playGreen : view.accent)
                                  : view.withAlpha(view.muted, 0.62)
                    border.width: selected ? 2 : 1
                    opacity: index === 2 && view.favoriteBusy ? 0.55 : 1
                    scale: selected ? 1.035 : actionHover.hovered ? 1.018 : 1
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: actionButton.index === 0 ? view.primaryAction
                              : actionButton.index === 1 ? "Game details"
                              : view.favoriteBusy ? "…" : view.favorite ? "★" : "☆"
                        color: actionButton.index === 0 ? view.background : view.ink
                        font.pixelSize: actionButton.index === 2 ? 22 : 16
                        font.weight: Font.Bold
                        font.letterSpacing: actionButton.index === 2 ? 0 : 0.7
                    }
                    HoverHandler { id: actionHover; onHoveredChanged: if (hovered) feedback.play("focus") }
                    TapHandler {
                        enabled: actionButton.index !== 2 || !view.favoriteBusy
                        onTapped: {
                            view.navigationZone = 1
                            view.actionIndex = actionButton.index
                            view.activateAction(actionButton.index)
                            view.forceActiveFocus()
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: view.detailsCurrent && view.selectedLocal && view.details.launch_status.length > 0
            text: view.details.launch_status
            color: view.details.can_launch ? view.accentCool : view.muted
            font.pixelSize: 11
            maximumLineCount: 2
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: coverFrame
        visible: !view.cinematicWheel && !view.wallView && !view.albumView && !view.hasPreviewVideo
        anchors.right: parent.right
        anchors.rightMargin: Math.max(74, parent.width * 0.075)
        anchors.top: brand.bottom
        anchors.topMargin: 58
        width: Math.min(330, parent.width * 0.21)
        height: width * 1.38
        radius: Math.min(32, view.cardRadius + 2)
        color: view.accentFor(view.selectedTitle)
        border.color: view.withAlpha(view.ink, 0.55)
        border.width: 1
        clip: true
        rotation: 1.5

        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(coverFrame.color, 1.2) }
            GradientStop { position: 1; color: Qt.darker(coverFrame.color, 1.65) }
        }

        Image {
            id: selectedCover
            anchors.fill: parent
            anchors.margins: 2
            source: view.active && !view.cinematicWheel && !view.wallView && !view.albumView ? view.coverUrl : ""
            asynchronous: true
            cache: true
            mipmap: true
            autoTransform: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: Math.max(1, Math.round(width * 1.6))
            sourceSize.height: Math.max(1, Math.round(height * 1.6))
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
        Text {
            anchors.centerIn: parent
            text: view.selectedTitle.length > 0
                  ? view.selectedTitle.charAt(0).toUpperCase() : "L"
            color: view.withAlpha(view.ink, 0.87)
            font.pixelSize: 104
            font.weight: Font.Black
            visible: selectedCover.status !== Image.Ready
        }
    }

    Row {
        id: backgroundVideoControls
        x: 70; y: footer.y - height - 12
        spacing: 8; z: 20
        visible: view.hasPreviewVideo && !view.overlayOpen && !view.platformWheelOpen && !view.wheelBrowseOnly
        CouchActionButton { text: couchVideo.paused ? "Play video" : "Pause video"; soundFeedback: feedback; inkColor: view.ink; panelColor: view.panel; accentColor: view.accent; onClicked: couchVideo.paused = !couchVideo.paused }
        CouchActionButton {
            text: view.videoMuted ? "Unmute all game videos" : "Mute all game videos"
            soundFeedback: feedback
            iconName: view.videoMuted ? "mute" : "volume"
            inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
            onClicked: view.videoMuteRequested()
            ToolTip.visible: hovered
            ToolTip.text: text
        }
        CouchActionButton { text: "Fullscreen"; soundFeedback: feedback; inkColor: view.ink; panelColor: view.panel; accentColor: view.accent; onClicked: view.videoRequested(couchVideo.source) }
    }
    CouchMediaStatus {
        id: gameMediaStatus
        objectName: "couchGameMediaStatus"
        x: 70; y: categoryRow.y + categoryRow.height + 6
        width: Math.min(600, parent.width - 140)
        visible: view.active && !!view.selectedGameId && !view.platformWheelOpen && !view.wheelBrowseOnly
        library: view.library
        gameId: view.selectedGameId
        videoKind: themeRequest.videoKind
        themePhase: themeRequest.phase
        themeProgress: themeRequest.progress
        themeMessage: themeRequest.status
        selectionPending: themeRequest.pending
        playbackError: couchVideo.errorMessage
        ink: view.ink
        muted: view.muted
        accent: view.accentCool
    }
    Text {
        anchors { left: gameCopy.left; top: gameCopy.bottom; topMargin: 14 }
        width: gameCopy.width
        visible: entrySelection.unavailable
        text: "This game is hidden by the current library filters. Its details are still available."
        color: view.accent; font.pixelSize: 14; wrapMode: Text.WordWrap
    }

    Item {
        id: shelfArea
        x: view.cinematicWheel ? parent.width - width : view.wallView ? 60 : 0
        y: view.cinematicWheel ? 0 : footer.y - height
        width: view.cinematicWheel ? parent.width * 0.44
                                   : view.wallView ? parent.width - 120 : parent.width
        height: view.cinematicWheel
                ? parent.height
                : view.wallView || view.albumView ? Math.max(180, footer.y - gameCopy.y - gameCopy.height - 28)
                : Math.max(250, parent.height * 0.30)

        Text {
            visible: !view.cinematicWheel
            anchors.left: parent.left
            anchors.leftMargin: view.cinematicWheel || view.wallView ? 8 : 70
            anchors.top: parent.top
            text: view.library.filtering ? "UPDATING…"
                  : view.currentShelfLabel + "  ·  "
                    + view.library.filtered_count + " GAMES"
            color: view.navigationZone === 2 ? view.accent : view.muted
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.4
        }

        CouchGameBrowser {
            id: shelf
            visible: !entrySelection.unavailable
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: view.cinematicWheel ? 0 : 25
            anchors.bottom: parent.bottom
            anchors.bottomMargin: view.wallView && backgroundVideoControls.visible
                                  ? backgroundVideoControls.height + 20 : 0
            library: view.library
            background: view.background
            panel: view.panel
            panelRaised: view.panelRaised
            ink: view.ink
            muted: view.muted
            accent: view.accent
            accentCool: view.accentCool
            cardRadius: view.cardRadius
            viewStyle: view.library.couch_view_style
            navigationActive: view.navigationZone === 2
            hoverSelectionEnabled: view.active && view.inputEnabled && !view.overlayOpen
                && !view.platformWheelOpen && !view.collectionWheelOpen && !view.variantWheelOpen
                && !view.searchOpen && !view.attractOpen && !view.launchStatusOverlayOpen && !view.downloadOverlayOpen
            onCardHovered: index => { view.navigationZone = 2; view.noteActivity() }

            onCurrentGameChanged: {
                if (!view.active)
                    return
                const previousGame = view.selectedGameId
                view.captureCurrentGame()
                if (previousGame.length > 0 && previousGame !== view.selectedGameId
                        && !view.searchOpen && !view.attractOpen)
                    feedback.play(view.movementCue)
                selectionDelay.restart()
            }
            onCardActivated: index => {
                view.noteActivity()
                view.navigationZone = 2
                const selectedAgain = shelf.currentIndex === index
                feedback.play(selectedAgain ? "confirm" : view.movementCue)
                shelf.currentIndex = index
                view.forceActiveFocus()
                if (selectedAgain) view.requestDetails()
            }
        }
    }

    SemanticIcon {
        objectName: "couchWheelPointer"
        visible: view.cinematicWheel && !view.platformWheelOpen
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: Math.max(28, view.width * 0.025); height: width * 1.4
        name: "play"; filled: true; color: "#fff3dc"; rotation: 180
        z: 4
    }
    Column {
        objectName: "couchWheelGameInfo"
        visible: view.wheelBrowseOnly && !view.platformWheelOpen
        anchors { left: parent.left; leftMargin: parent.width * 0.035; bottom: footer.top; bottomMargin: 16 }
        width: parent.width * 0.52; spacing: 5
        Text {
            width: parent.width
            text: view.selectedPlatform + (view.browsing.release_date ? "  ·  " + view.browsing.release_date.slice(0, 4) : "")
            color: "#dedee4"; font.pixelSize: Math.max(13, view.height * 0.016)
            style: Text.Outline; styleColor: "#16181c"; elide: Text.ElideRight
        }
        Text {
            width: parent.width; text: view.selectedTitle
            color: "white"; font.pixelSize: Math.max(22, view.height * 0.031); font.weight: Font.DemiBold
            style: Text.Outline; styleColor: "#16181c"; elide: Text.ElideRight
        }
    }

    ParallelAnimation {
        id: selectionReveal
        NumberAnimation { target: gameCopy; property: "opacity"; from: 0.45; to: 1; duration: 240 }
        NumberAnimation { target: copyEntrance; property: "x"; from: 22; to: 0; duration: 280; easing.type: Easing.OutCubic }
    }
    NumberAnimation { id: platformReveal; target: platformInfo; property: "opacity"; from: 0.4; to: 1; duration: 260; easing.type: Easing.OutCubic }

    Row {
        id: footer
        anchors.left: parent.left
        anchors.leftMargin: 70
        anchors.right: parent.right
        anchors.rightMargin: 70
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        height: 28
        spacing: 22

        Text {
            text: view.gamepad.connected_count > 0
                  ? "D-PAD / STICK  MOVE"
                  : view.cinematicWheel ? "↑ ↓  BROWSE" : "← →  BROWSE"
            color: view.muted
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
        Text {
            text: view.gamepad.connected_count > 0
                  ? view.gamepad.button_label("accept") + "  SELECT"
                  : view.cinematicWheel ? "← →  MOVE" : "↑ ↓  MOVE"
            color: view.muted
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
        Text {
            text: view.gamepad.connected_count > 0
                  ? view.gamepad.button_label("favorite") + "  FAVORITE"
                  : "ENTER  SELECT"
            color: view.muted
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
        Text {
            text: view.gamepad.connected_count > 0
                  ? view.gamepad.button_label("details") + "  DETAILS"
                  : "CTRL+F  FAVORITE"
            color: view.muted
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
        Text {
            visible: view.gamepad.connected_count === 0
            text: "TYPE TO SEARCH · F2 MIC · F4 HANDS-FREE · CTRL+A ATTRACT · CTRL+V VIEW · CTRL+P MUSIC"
            color: view.muted
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
        Item { width: Math.max(0, parent.width - 760); height: 1 }
        Text {
            text: view.gamepad.connected_count > 0
                  ? view.gamepad.button_label("back") + "  DESKTOP MODE"
                  : "ESC  DESKTOP MODE"
            color: view.muted
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }
    }

    CouchBackgroundMusic {
        id: couchMusic
        anchors.right: parent.right
        anchors.rightMargin: 70
        anchors.bottom: footer.top
        anchors.bottomMargin: 14
        z: 40
        width: Math.min(380, Math.max(300, view.width * 0.24))
        height: 68
        library: view.library
        details: view.browsing
        selectedGameId: view.selectedGameId
        active: view.active
        microphoneActive: view.audioSuppressedForVoice
        blocked: !view.inputEnabled || view.launchStatusOverlayOpen
                 || (couchVideo.playing && !view.videoMuted)
                 || view.downloadOverlayOpen
                 || view.platformWheelOpen
                 || view.collectionWheelOpen
                 || view.variantWheelOpen
        panelColor: view.panel
        inkColor: view.ink
        mutedColor: view.muted
        accentColor: view.accent
    }

    Rectangle {
        id: attractOverlay
        anchors.fill: parent
        z: 42
        visible: view.attractOpen
        color: view.background

        Image {
            anchors.fill: parent
            source: view.attractOpen ? view.library.couch_theme_background_image : ""
            asynchronous: true
            cache: true
            autoTransform: true
            fillMode: Image.PreserveAspectCrop
            opacity: status === Image.Ready ? 1 : 0
        }

        Image {
            anchors.fill: parent
            source: view.attractOpen ? view.heroUrl : ""
            asynchronous: true
            cache: true
            autoTransform: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(1920, 1080)
            retainWhileLoading: true
            opacity: status === Image.Ready ? 0.88 : 0
            Behavior on opacity { NumberAnimation { duration: 420 } }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: view.withAlpha(view.background, Math.min(0.99, view.heroScrimOpacity + 0.3)) }
                GradientStop { position: 0.46; color: view.withAlpha(view.background, Math.min(0.9, view.heroScrimOpacity + 0.1)) }
                GradientStop { position: 0.78; color: view.withAlpha(view.background, view.heroScrimOpacity * 0.42) }
                GradientStop { position: 1; color: view.withAlpha(view.background, Math.min(0.8, view.heroScrimOpacity + 0.04)) }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.58
            gradient: Gradient {
                GradientStop { position: 0; color: view.withAlpha(view.background, 0) }
                GradientStop { position: 0.34; color: view.withAlpha(view.background, 0.72) }
                GradientStop { position: 1; color: view.background }
            }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.top: parent.top
            anchors.topMargin: 42
            spacing: 13

            AppIcon {
                width: 42
                height: 42
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: "LUNCHPAIL"
                    color: view.ink
                    font.pixelSize: 17
                    font.weight: Font.Black
                    font.letterSpacing: 1.8
                }
                Text {
                    text: "ATTRACT MODE"
                    color: view.accent
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 46
            anchors.right: parent.right
            anchors.rightMargin: 62
            width: attractModeLabel.implicitWidth + 30
            height: 34
            radius: Math.max(8, view.cardRadius - 5)
            color: view.withAlpha(view.panel, 0.74)
            border.color: view.withAlpha(view.muted, 0.52)
            Text {
                id: attractModeLabel
                anchors.centerIn: parent
                text: view.attractReason === "idle" ? "IDLE SCREENSAVER" : "MANUAL SHOWCASE"
                color: view.muted
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1
            }
        }

        Rectangle {
            id: attractCoverShadow
            anchors.right: parent.right
            anchors.rightMargin: Math.max(74, parent.width * 0.075)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 30
            width: Math.min(360, parent.width * 0.22)
            height: width * 1.38
            radius: Math.min(32, view.cardRadius + 8)
            color: view.withAlpha(view.background, 0.7)
            rotation: 2.5

            Rectangle {
                id: attractCoverSurface
                anchors.fill: parent
                anchors.margins: 10
                radius: Math.min(32, view.cardRadius + 4)
                color: view.accentFor(view.selectedTitle)
                border.color: view.withAlpha(view.ink, 0.55)
                clip: true
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.lighter(attractCoverSurface.color, 1.2)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.darker(attractCoverSurface.color, 1.65)
                    }
                }
                Image {
                    id: attractCoverImage
                    anchors.fill: parent
                    anchors.margins: 2
                    source: view.attractOpen ? view.coverUrl : ""
                    asynchronous: true
                    cache: true
                    mipmap: true
                    autoTransform: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: Math.max(1, Math.round(width * 1.5))
                    sourceSize.height: Math.max(1, Math.round(height * 1.5))
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 280 } }
                }
                Text {
                    anchors.centerIn: parent
                    visible: attractCoverImage.status !== Image.Ready
                    text: view.selectedTitle.length > 0
                          ? view.selectedTitle.charAt(0).toUpperCase() : "L"
                    color: view.withAlpha(view.ink, 0.85)
                    font.pixelSize: 92
                    font.weight: Font.Black
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: Math.max(62, parent.width * 0.065)
            anchors.right: attractCoverShadow.left
            anchors.rightMargin: Math.max(70, parent.width * 0.055)
            anchors.bottom: attractFooter.top
            anchors.bottomMargin: 44
            spacing: 14

            Rectangle {
                width: 74
                height: 5
                radius: 3
                color: view.accent
            }
            Text {
                width: parent.width
                text: view.selectedPlatform.toUpperCase()
                color: view.accent
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.5
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: view.selectedTitle
                color: view.ink
                font.pixelSize: Math.max(38, Math.min(64, attractOverlay.width / 30))
                font.weight: Font.Black
                lineHeight: 0.98
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                width: Math.min(parent.width, 850)
                visible: view.browsing.description.length > 0
                text: view.browsing.description
                color: view.withAlpha(view.ink, 0.84)
                font.pixelSize: 15
                lineHeight: 1.28
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
            Row {
                spacing: 10
                Rectangle {
                    width: attractStateLabel.implicitWidth + 22
                    height: 30
                    radius: Math.max(8, view.cardRadius - 6)
                    color: view.selectedLocal ? view.withAlpha(view.playGreen, 0.24)
                           : view.selectedDownloadable ? view.withAlpha(view.accent, 0.24)
                                                       : view.withAlpha(view.panelRaised, 0.76)
                    border.color: view.selectedLocal ? view.playGreen
                                  : view.selectedDownloadable ? view.accent
                                                              : view.withAlpha(view.muted, 0.58)
                    Text {
                        id: attractStateLabel
                        anchors.centerIn: parent
                        text: view.selectedLocal ? "INSTALLED"
                              : view.selectedDownloadable ? "MINERVA AVAILABLE"
                                : "CATALOG"
                        color: view.selectedLocal ? view.playGreen
                               : view.selectedDownloadable ? view.accent : view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }
                Rectangle {
                    visible: view.favorite
                    width: attractFavoriteLabel.implicitWidth + 22
                    height: 30
                    radius: Math.max(8, view.cardRadius - 6)
                    color: view.withAlpha(view.accent, 0.22)
                    border.color: view.accent
                    Text {
                        id: attractFavoriteLabel
                        anchors.centerIn: parent
                        text: "★ FAVORITE"
                        color: view.accent
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        Rectangle {
            id: attractFooter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 78
            color: view.withAlpha(view.panel, 0.86)

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 2
                color: view.withAlpha(view.muted, 0.5)
                Rectangle {
                    width: parent.width * view.attractProgress
                    height: parent.height
                    color: view.accent
                }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 62
                anchors.verticalCenter: parent.verticalCenter
                spacing: 28
                Text {
                    text: view.gamepad.connected_count > 0
                          ? "D-PAD / STICK  NEXT GAME" : "← →  NEXT GAME"
                    color: view.muted
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 0.8
                }
                Text {
                    text: view.gamepad.connected_count > 0
                          ? view.gamepad.button_label("accept") + "  GAME MENU"
                          : "ENTER  GAME MENU"
                    color: view.ink
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 0.8
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 62
                anchors.verticalCenter: parent.verticalCenter
                text: view.gamepad.connected_count > 0
                      ? view.gamepad.button_label("back") + "  RETURN TO BROWSING"
                      : "ESC  RETURN TO BROWSING"
                color: view.muted
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 0.8
            }
        }

        TapHandler {
            onTapped: {
                view.stopAttractMode()
                view.openOverlay("menu")
            }
        }
    }

    CouchDownloadScreen {
        id: downloadScreen
        anchors.fill: parent
        z: 58
        active: view.downloadOverlayOpen && view.detailsCurrent
        details: view.details
        gameTitle: view.selectedTitle
        platformName: view.selectedPlatform
        coverUrl: view.coverUrl
        heroUrl: view.heroUrl
        backgroundColor: view.background
        panelColor: view.panel
        panelRaisedColor: view.panelRaised
        inkColor: view.ink
        mutedColor: view.muted
        accentColor: view.accent
        accentCoolColor: view.accentCool
        dangerColor: view.danger
        cardRadius: view.cardRadius
        inputHint: view.gamepad.connected_count > 0
                   ? view.gamepad.button_label("accept") + "  SELECT   ·   "
                     + view.gamepad.button_label("back") + "  RETURN"
                   : "ENTER  SELECT   ·   ESC  RETURN"
        onCloseRequested: view.closeDownloadOverlay()
        onConfigureRequested: {
            view.downloadOverlayOpen = false
            view.settingsRequested("qbittorrent")
        }
        onImportTorrentRequested: {
            view.downloadOverlayOpen = false
            view.torrentImportRequested(view.selectedGameId,
                                        view.selectedDatabaseId,
                                        view.selectedTitle,
                                        view.selectedPlatform)
        }
    }

    CouchLaunchScreen {
        id: launchStatusOverlay
        anchors.fill: parent
        z: 60
        active: view.launchStatusOverlayOpen && view.detailsCurrent
        details: view.details
        gameTitle: view.selectedTitle
        platformName: view.selectedPlatform
        coverUrl: view.coverUrl
        heroUrl: view.heroUrl
        themeBackgroundUrl: view.library.couch_theme_background_image
        backgroundColor: view.background
        panelColor: view.panel
        panelRaisedColor: view.panelRaised
        inkColor: view.ink
        mutedColor: view.muted
        accentColor: view.accent
        accentCoolColor: view.accentCool
        dangerColor: view.danger
        cardRadius: view.cardRadius
        inputHint: view.gamepad.connected_count > 0
                   ? view.gamepad.button_label("accept")
                     + (view.details.launch_busy ? "  CANCEL   ·   " : "  CLOSE   ·   ")
                     + view.gamepad.button_label("details") + "  GAME DETAILS   ·   "
                     + view.gamepad.button_label("menu") + "  GAME MENU   ·   "
                     + view.gamepad.button_label("back") + "  CLOSE"
                   : (view.details.launch_busy ? "ENTER  CANCEL   ·   " : "ENTER  CLOSE   ·   ")
                     + "CTRL+D  GAME DETAILS   ·   CTRL+M  GAME MENU   ·   ESC  CLOSE"
        onCloseRequested: view.closeLaunchStatus()
        onCancelRequested: view.details.cancel_launch()
        onDetailsRequested: {
            view.launchCompletionPending = false
            view.launchStatusOverlayOpen = false
            view.requestDetails()
        }
        onMenuRequested: {
            view.launchCompletionPending = false
            view.launchStatusOverlayOpen = false
            view.openOverlay("menu")
        }
    }
    Rectangle {
        id: platformWheelOverlay
        anchors.fill: parent
        z: 45
        visible: view.platformWheelOpen
        color: view.withAlpha(view.background, 0.93)

        CouchVideoPreview {
            id: platformVideo
            objectName: "platformBackgroundVideo"
            anchors.fill: parent
            backgroundMode: true
            source: platformPresentation.videoUrl
            visible: source.toString().length > 0
            active: view.active && view.platformWheelOpen && view.inputEnabled && visible && !view.details.game_running
            muted: view.videoMuted || view.audioSuppressedForVoice
            label: "PLATFORM VIDEO THEME"
        }
        Rectangle {
            anchors.fill: parent
            opacity: view.cinematicWheel ? (platformVideo.playing ? 0.08 : 0.5) : platformVideo.playing ? 0.32 : 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: view.withAlpha(view.background, 0.96) }
                GradientStop { position: 0.55; color: view.withAlpha(view.panel, 0.89) }
                GradientStop { position: 1; color: view.withAlpha(view.background, 0.76) }
            }
        }

        Rectangle {
            id: platformWheelPanel
            scale: view.platformWheelOpen ? 1 : 0.98
            opacity: view.platformWheelOpen ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 220 } }
            anchors.centerIn: parent
            width: view.cinematicWheel ? parent.width : parent.width - 100
            height: view.cinematicWheel ? parent.height : parent.height - 90
            radius: Math.min(32, view.cardRadius + 10)
            color: view.cinematicWheel ? "transparent" : view.withAlpha(view.panel, platformVideo.playing ? 0.22 : 0.97)
            border.color: view.withAlpha(view.muted, 0.58)
            border.width: view.cinematicWheel ? 0 : 1
            clip: true

            Item {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 150; z: 3
                HoverHandler { id: platformToolbarHover; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad }
            }
            SemanticIcon {
                objectName: "couchPlatformWheelPointer"
                visible: view.cinematicWheel
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                width: Math.max(28, view.width * 0.025); height: width * 1.4
                name: "play"; filled: true; color: "#fff3dc"; rotation: 180
                z: 1
            }
            Column {
                visible: view.cinematicWheel
                anchors { left: parent.left; leftMargin: parent.width * 0.035; bottom: parent.bottom; bottomMargin: 70 }
                width: parent.width * 0.50; spacing: 8
                Text {
                    width: parent.width; text: platformPresentation.platform
                    color: "white"; font.pixelSize: Math.max(24, view.height * 0.035); font.weight: Font.DemiBold
                    style: Text.Outline; styleColor: "#16181c"; wrapMode: Text.WordWrap
                }
                Text {
                    text: "ENTER  BROWSE GAMES   ·   D  SYSTEM MEDIA"
                    color: "#dedee4"; font.pixelSize: 12
                    style: Text.Outline; styleColor: "#16181c"
                }
            }

            Rectangle {
                visible: !view.wheelBrowseOnly
                z: 2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 118
                color: view.withAlpha(view.panelRaised, 0.86)

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 42
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: "CHOOSE A PLATFORM"
                        color: view.ink
                        font.pixelSize: 24
                        font.weight: Font.Black
                        font.letterSpacing: 1.3
                    }
                    Text {
                        text: view.library.platform_count + " platforms · " + view.viewLabel
                        color: view.muted
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.4
                    }
                }

                CouchActionButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 94
                    anchors.verticalCenter: parent.verticalCenter
                    width: 190; height: 44
                    text: view.viewLabel + "  ·  Ctrl+V"
                    soundFeedback: feedback; soundCue: ""
                    inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
                    Accessible.name: "Change platform and game view"
                    onClicked: view.toggleViewStyle()
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 32
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 13
                    color: platformCloseHover.hovered
                           ? view.withAlpha(view.panelRaised, 0.9)
                           : view.withAlpha(view.panel, 0.72)
                    border.color: platformCloseHover.hovered
                                  ? view.accent : view.withAlpha(view.muted, 0.55)
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: view.ink
                        font.pixelSize: 23
                    }
                    HoverHandler { id: platformCloseHover; onHoveredChanged: if (hovered) feedback.play("focus") }
                    TapHandler { onTapped: view.closePlatformWheel() }
                }
            }

            CouchPlatformBrowser {
                id: platformWheel
                x: view.cinematicWheel ? parent.width - width : 24
                width: parent.width * (view.cinematicWheel ? 0.44 : 0.62)
                anchors.top: parent.top
                anchors.topMargin: view.cinematicWheel ? 0 : 128
                anchors.bottom: parent.bottom
                anchors.bottomMargin: view.cinematicWheel ? 0 : 82
                library: view.library
                viewStyle: view.library.couch_view_style
                panel: view.panel; ink: view.ink; muted: view.muted; accent: view.accent
                hoverSelectionEnabled: view.active && view.inputEnabled && view.platformWheelOpen
                onCurrentIndexChanged: {
                    if (currentIndex < 0) return
                    const changed = view.platformWheelIndex !== currentIndex
                    view.platformWheelIndex = currentIndex
                    if (changed && view.active && view.platformWheelOpen)
                        feedback.play(view.movementCue)
                }
                onActivated: index => view.choosePlatform(index)
            }

            Rectangle {
                visible: !view.cinematicWheel
                x: platformInfo.x - 16; y: platformInfo.y - 16
                width: platformInfo.width + 32
                height: Math.min(platformInfo.height + 32, platformPresentation.height + 32)
                radius: 20
                color: view.withAlpha(view.panel, 0.88)
                border.color: view.withAlpha(view.ink, 0.12)
            }
            MomentumFlickable {
                id: platformInfo
                visible: !view.cinematicWheel
                anchors { left: platformWheel.right; right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 145; bottomMargin: 90; leftMargin: 40; rightMargin: 40 }
                clip: true; contentWidth: width; contentHeight: platformPresentation.height
              Column {
                id: platformPresentation
                width: parent.width
                property string platform: {
                    // The first index can remain zero while the async catalog
                    // arrives; invokable calls do not track that data change.
                    view.library.platform_count
                    return view.library.platform_name_at(view.platformWheelIndex)
                }
                onPlatformChanged: if (view.active && view.platformWheelOpen) platformReveal.restart()
                property url videoUrl: { view.mediaRevision; return view.library.platform_media_url(platform, "video") }
                readonly property bool compact: view.height < 850
                spacing: compact ? 12 : 24
                Image {
                    id: platformHeroLogo
                    width: parent.width; height: status === Image.Ready ? (platformPresentation.compact ? 64 : 120) : 0
                    source: { view.mediaRevision; return view.library.platform_media_url(platformPresentation.platform, "clear-logo") }
                    asynchronous: true; fillMode: Image.PreserveAspectFit; sourceSize: Qt.size(800, 260)
                }
                Text {
                    width: parent.width; text: platformPresentation.platform
                    color: view.ink; font.pixelSize: platformPresentation.compact ? 22 : 30; font.weight: Font.Bold
                    wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 2; elide: Text.ElideRight
                }
                Row {
                    spacing: 8; visible: platformVideo.visible
                    CouchActionButton { text: platformVideo.paused ? "Play" : "Pause"; soundFeedback: feedback; inkColor: view.ink; panelColor: view.panel; accentColor: view.accent; onClicked: platformVideo.paused = !platformVideo.paused }
                    CouchActionButton {
                        text: view.videoMuted ? "Unmute all game videos" : "Mute all game videos"
                        soundFeedback: feedback
                        iconName: view.videoMuted ? "mute" : "volume"
                        inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
                        onClicked: view.videoMuteRequested()
                        ToolTip.visible: hovered
                        ToolTip.text: text
                    }
                    CouchActionButton { text: "Fullscreen"; soundFeedback: feedback; inkColor: view.ink; panelColor: view.panel; accentColor: view.accent; onClicked: view.videoRequested(platformVideo.source) }
                }
                Text {
                    width: parent.width
                    text: platformPresentation.videoUrl.toString() ? "System video theme ready"
                          : themeRequest.status || "Select a system to find its video theme."
                    color: view.muted; font.pixelSize: 14
                    wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 3; elide: Text.ElideRight
                }
                InlineProgressBar {
                    width: parent.width; height: 5
                    visible: !platformPresentation.videoUrl.toString()
                             && ["queued", "finding", "downloading"].indexOf(themeRequest.phase) >= 0
                    from: 0; to: 100
                    value: Math.max(0, themeRequest.progress)
                    indeterminate: themeRequest.progress <= 0
                    fillColor: view.accentCool
                    trackColor: view.withAlpha(view.muted, 0.2)
                }
                Text {
                    width: parent.width
                    text: "Browse this system’s games, or customize its wheel artwork and video theme."
                    color: view.muted; font.pixelSize: 16; lineHeight: 1.3
                    wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                }
                CouchActionButton {
                    width: parent.width; height: 52
                    text: (view.gamepad.connected_count > 0 ? view.gamepad.button_label("details") : "D") + "  ·  System media"
                    soundFeedback: feedback
                    inkColor: view.ink; panelColor: view.panel; accentColor: view.accent
                    contentItem: LbButtonLabel { control: parent; pixelSize: 18 }
                    onClicked: view.systemMediaRequested(platformPresentation.platform)
                }
              }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: view.cinematicWheel ? 46 : 72
                color: view.withAlpha(view.background, view.cinematicWheel ? 0.5 : 0.86)

                Row {
                    anchors.centerIn: parent
                    spacing: 28
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? "D-PAD / STICK  BROWSE" : "↑ ↓  BROWSE"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("accept") + "  SELECT"
                              : "ENTER  SELECT"
                        color: view.accent
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("back") + "  CANCEL"
                              : "ESC  CANCEL"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }
            }
        }
    }

    Rectangle {
        id: collectionWheelOverlay
        anchors.fill: parent
        z: 46
        visible: view.collectionWheelOpen
        color: view.withAlpha(view.background, 0.93)

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: view.withAlpha(view.background, 0.96) }
                GradientStop { position: 0.55; color: view.withAlpha(view.panel, 0.89) }
                GradientStop { position: 1; color: view.withAlpha(view.background, 0.76) }
            }
        }

        Rectangle {
            id: collectionWheelPanel
            anchors.centerIn: parent
            width: Math.min(940, parent.width - 180)
            height: Math.min(860, parent.height - 120)
            radius: Math.min(32, view.cardRadius + 10)
            color: view.withAlpha(view.panel, 0.97)
            border.color: view.withAlpha(view.muted, 0.58)
            border.width: 1
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 118
                color: view.withAlpha(view.panelRaised, 0.86)

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 42
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: "CHOOSE A COLLECTION"
                        color: view.ink
                        font.pixelSize: 24
                        font.weight: Font.Black
                        font.letterSpacing: 1.3
                    }
                    Text {
                        text: view.library.collection_count + " collection"
                              + (view.library.collection_count === 1 ? "" : "s")
                              + " · exact saved identity"
                        color: view.muted
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.4
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 32
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 13
                    color: collectionCloseHover.hovered
                           ? view.withAlpha(view.panelRaised, 0.9)
                           : view.withAlpha(view.panel, 0.72)
                    border.color: collectionCloseHover.hovered
                                  ? view.accent : view.withAlpha(view.muted, 0.55)
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: view.ink
                        font.pixelSize: 23
                    }
                    HoverHandler { id: collectionCloseHover }
                    TapHandler { onTapped: view.closeCollectionWheel() }
                }
            }

            MomentumListView {
                id: collectionWheel
                anchors.left: parent.left
                anchors.leftMargin: 34
                anchors.right: parent.right
                anchors.rightMargin: 34
                anchors.top: parent.top
                anchors.topMargin: 128
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 82
                model: view.library.collection_count
                clip: true
                reuseItems: true
                cacheBuffer: Math.max(0, Math.round(height))
                spacing: 7
                boundsBehavior: Flickable.StopAtBounds
                snapMode: ListView.SnapToItem
                preferredHighlightBegin: height * 0.5 - 49
                preferredHighlightEnd: height * 0.5 + 49
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightMoveDuration: 120
                onCurrentIndexChanged: {
                    if (currentIndex >= 0)
                        view.collectionWheelIndex = currentIndex
                }

                delegate: Item {
                    id: collectionRow
                    required property int index
                    property int revision: view.library.collection_revision
                    property string collectionId: {
                        revision
                        return view.library.collection_id_at(index)
                    }
                    property string collectionName: {
                        revision
                        return view.library.collection_name_at(index)
                    }
                    property string description: {
                        revision
                        return view.library.collection_description_at(index)
                    }
                    property string kind: {
                        revision
                        return view.library.collection_kind_at(index)
                    }
                    property string ruleSummary: {
                        revision
                        return view.library.collection_rule_summary_at(index)
                    }
                    property int gameCount: {
                        revision
                        return view.library.collection_game_count_at(index)
                    }
                    property bool selected: collectionWheel.currentIndex === index
                    property int distance: Math.abs(index - collectionWheel.currentIndex)
                    width: collectionWheel.width
                    height: selected ? 98 : 80
                    opacity: selected ? 1 : distance <= 2 ? 0.74 : 0.42
                    scale: selected ? 1 : 0.975
                    Accessible.name: collectionName + ", " + gameCount
                                     + (gameCount === 1 ? " game" : " games")
                    Behavior on height { NumberAnimation { duration: 110 } }
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 110 } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: collectionRow.selected ? 0 : 16
                        anchors.rightMargin: collectionRow.selected ? 0 : 16
                        radius: 16
                        color: collectionRow.selected
                               ? view.withAlpha(view.panelRaised, 0.9)
                               : collectionHover.hovered
                                 ? view.withAlpha(view.panelRaised, 0.55)
                                 : "transparent"
                        border.color: collectionRow.selected ? view.accent : "transparent"
                        border.width: collectionRow.selected ? 2 : 0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: collectionRow.selected ? 56 : 46
                            height: width
                            radius: 15
                            color: view.accentFor(collectionRow.collectionName)
                            border.color: view.withAlpha(view.ink, 0.51)
                            Text {
                                anchors.centerIn: parent
                                text: collectionRow.kind === "smart" ? "⚡" : "▣"
                                color: view.withAlpha(view.ink, 0.97)
                                font.pixelSize: collectionRow.selected ? 24 : 19
                                font.weight: Font.Black
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: collectionRow.selected ? 94 : 80
                            anchors.right: collectionCountColumn.left
                            anchors.rightMargin: 28
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Row {
                                spacing: 10
                                Text {
                                    text: collectionRow.collectionName
                                    color: view.ink
                                    font.pixelSize: collectionRow.selected ? 19 : 15
                                    font.weight: collectionRow.selected
                                                 ? Font.Black : Font.DemiBold
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth,
                                                    collectionWheel.width * 0.46)
                                }
                                Text {
                                    visible: collectionRow.collectionId
                                             === view.currentCollectionId
                                    text: "CURRENT SHELF"
                                    color: view.accentCool
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Text {
                                width: parent.width
                                text: collectionRow.description.length > 0
                                      ? collectionRow.description
                                      : collectionRow.kind === "smart"
                                        ? collectionRow.ruleSummary
                                        : "A manually curated game shelf"
                                color: view.muted
                                font.pixelSize: 10
                                maximumLineCount: collectionRow.selected ? 2 : 1
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                            }
                        }

                        Column {
                            id: collectionCountColumn
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                anchors.right: parent.right
                                text: collectionRow.gameCount.toLocaleString(
                                          Qt.locale(), "f", 0)
                                color: collectionRow.selected ? view.accent : view.ink
                                font.pixelSize: collectionRow.selected ? 18 : 14
                                font.weight: Font.Black
                            }
                            Text {
                                anchors.right: parent.right
                                text: collectionRow.kind === "smart" ? "SMART" : "CURATED"
                                color: view.muted
                                font.pixelSize: 8
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                            }
                        }

                        HoverHandler { id: collectionHover }
                        TapHandler { onTapped: view.chooseCollection(collectionRow.index) }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: view.library.collection_count === 0
                    width: Math.min(520, parent.width - 80)
                    text: "No collections yet\n\nCreate a manual or smart collection in Desktop Mode, then it will appear here automatically."
                    color: view.muted
                    font.pixelSize: 15
                    lineHeight: 1.35
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 72
                color: view.withAlpha(view.background, 0.86)

                Row {
                    anchors.centerIn: parent
                    spacing: 28
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? "D-PAD / STICK  BROWSE" : "↑ ↓  BROWSE"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        text: view.library.collection_count > 0
                              ? (view.gamepad.connected_count > 0
                                 ? view.gamepad.button_label("accept") + "  SELECT"
                                 : "ENTER  SELECT")
                              : "DESKTOP MODE  CREATE COLLECTION"
                        color: view.accent
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("back") + "  CANCEL"
                              : "ESC  CANCEL"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }
            }
        }
    }

    Rectangle {
        id: variantWheelOverlay
        anchors.fill: parent
        z: 47
        visible: view.variantWheelOpen
        color: view.withAlpha(view.background, 0.94)

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: view.withAlpha(view.background, 0.97) }
                GradientStop { position: 0.55; color: view.withAlpha(view.panel, 0.9) }
                GradientStop { position: 1; color: view.withAlpha(view.background, 0.78) }
            }
        }

        Rectangle {
            id: variantWheelPanel
            anchors.centerIn: parent
            width: Math.min(1020, parent.width - 180)
            height: Math.min(860, parent.height - 120)
            radius: Math.min(32, view.cardRadius + 10)
            color: view.withAlpha(view.panel, 0.98)
            border.color: view.withAlpha(view.muted, 0.58)
            border.width: 1
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 132
                color: view.withAlpha(view.panelRaised, 0.87)

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 42
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: "CHOOSE A RELEASE"
                        color: view.ink
                        font.pixelSize: 24
                        font.weight: Font.Black
                        font.letterSpacing: 1.3
                    }
                    Text {
                        text: view.details.variant_count + " exact catalog releases · region and version preferences"
                        color: view.muted
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.35
                    }
                    Text {
                        text: view.details.media_visible
                              ? "Cached video or manual media is available for this record."
                              : "Media and acquisition state stay attached to each exact release."
                        color: view.details.media_visible ? view.accentCool : view.muted
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 32
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 13
                    color: variantCloseHover.hovered
                           ? view.withAlpha(view.panelRaised, 0.9)
                           : view.withAlpha(view.panel, 0.72)
                    border.color: variantCloseHover.hovered
                                  ? view.accent : view.withAlpha(view.muted, 0.55)
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: view.ink
                        font.pixelSize: 23
                    }
                    HoverHandler { id: variantCloseHover }
                    TapHandler { onTapped: view.closeVariantWheel() }
                }
            }

            MomentumListView {
                id: variantWheel
                anchors.left: parent.left
                anchors.leftMargin: 34
                anchors.right: parent.right
                anchors.rightMargin: 34
                anchors.top: parent.top
                anchors.topMargin: 142
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 82
                model: view.details.variant_count
                clip: true
                reuseItems: true
                cacheBuffer: Math.max(0, Math.round(height))
                spacing: 7
                boundsBehavior: Flickable.StopAtBounds
                snapMode: ListView.SnapToItem
                preferredHighlightBegin: height * 0.5 - 53
                preferredHighlightEnd: height * 0.5 + 53
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightMoveDuration: 120
                onCurrentIndexChanged: {
                    if (currentIndex >= 0)
                        view.variantWheelIndex = currentIndex
                }

                delegate: Item {
                    id: variantRow
                    required property int index
                    property int revision: view.details.detail_revision
                    property string releaseTitle: {
                        revision
                        return view.details.variant_title_at(index)
                    }
                    property string releaseLabel: {
                        revision
                        return view.details.variant_label_at(index)
                    }
                    property string releaseStatus: {
                        revision
                        const value = view.details.variant_status_at(index)
                        return value.length > 0 ? value : "CATALOG"
                    }
                    property bool current: {
                        revision
                        return view.details.variant_is_current_at(index)
                    }
                    property bool local: {
                        revision
                        return view.details.variant_is_local_at(index)
                    }
                    property bool downloadable: {
                        revision
                        return view.details.variant_is_downloadable_at(index)
                    }
                    property bool selected: variantWheel.currentIndex === index
                    property int distance: Math.abs(index - variantWheel.currentIndex)
                    width: variantWheel.width
                    height: selected ? 112 : 88
                    opacity: selected ? 1 : distance <= 2 ? 0.76 : 0.45
                    scale: selected ? 1 : 0.975
                    Accessible.name: releaseLabel + ", " + releaseStatus
                    Behavior on height { NumberAnimation { duration: 110 } }
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 110 } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: variantRow.selected ? 0 : 16
                        anchors.rightMargin: variantRow.selected ? 0 : 16
                        radius: 16
                        color: variantRow.selected
                               ? view.withAlpha(view.panelRaised, 0.92)
                               : variantHover.hovered
                                 ? view.withAlpha(view.panelRaised, 0.56)
                                 : "transparent"
                        border.color: variantRow.selected ? view.accent : "transparent"
                        border.width: variantRow.selected ? 2 : 0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: variantRow.selected ? 62 : 50
                            height: width
                            radius: 16
                            color: view.accentFor(variantRow.releaseTitle)
                            border.color: view.withAlpha(view.ink, 0.51)
                            Text {
                                anchors.centerIn: parent
                                text: variantRow.current ? "✓" : "◇"
                                color: view.withAlpha(view.ink, 0.97)
                                font.pixelSize: variantRow.selected ? 25 : 20
                                font.weight: Font.Black
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: variantRow.selected ? 98 : 84
                            anchors.right: variantStatusColumn.left
                            anchors.rightMargin: 24
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Row {
                                spacing: 10
                                Text {
                                    text: variantRow.releaseLabel
                                    color: view.ink
                                    font.pixelSize: variantRow.selected ? 19 : 15
                                    font.weight: variantRow.selected
                                                 ? Font.Black : Font.DemiBold
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth,
                                                    variantWheel.width * 0.48)
                                }
                                Text {
                                    visible: variantRow.current
                                    text: "CURRENT"
                                    color: view.accentCool
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Text {
                                width: parent.width
                                text: variantRow.releaseTitle
                                color: view.muted
                                font.pixelSize: 10
                                maximumLineCount: variantRow.selected ? 2 : 1
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                            }
                        }

                        Column {
                            id: variantStatusColumn
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Rectangle {
                                anchors.right: parent.right
                                width: variantStatusText.implicitWidth + 16
                                height: 22
                                radius: 7
                                color: variantRow.releaseStatus === "CURRENT"
                                       ? view.withAlpha(view.accentCool, 0.2)
                                       : variantRow.releaseStatus === "INSTALLED"
                                         ? view.withAlpha(view.accentCool, 0.14)
                                         : variantRow.releaseStatus === "MINERVA"
                                           ? view.withAlpha(view.accent, 0.2)
                                           : view.withAlpha(view.muted, 0.14)
                                border.color: variantRow.releaseStatus === "CURRENT"
                                              ? view.accentCool
                                              : variantRow.releaseStatus === "MINERVA"
                                                ? view.accent : view.withAlpha(view.muted, 0.5)
                                Text {
                                    id: variantStatusText
                                    anchors.centerIn: parent
                                    text: variantRow.releaseStatus
                                    color: variantRow.releaseStatus === "CURRENT"
                                           || variantRow.releaseStatus === "INSTALLED"
                                           ? view.accentCool
                                           : variantRow.releaseStatus === "MINERVA"
                                             ? view.accent : view.muted
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.55
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                text: variantRow.local ? "INSTALLED"
                                      : variantRow.downloadable ? "DOWNLOADABLE"
                                                                : "CATALOG ONLY"
                                color: variantRow.local ? view.accentCool
                                      : variantRow.downloadable ? view.accent : view.muted
                                font.pixelSize: 8
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }
                        }

                        HoverHandler { id: variantHover }
                        TapHandler {
                            enabled: !variantRow.current && !view.details.loading
                            onTapped: view.chooseVariant(variantRow.index)
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 72
                color: view.withAlpha(view.background, 0.86)

                Row {
                    anchors.centerIn: parent
                    spacing: 28
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? "D-PAD / STICK  BROWSE" : "↑ ↓  BROWSE"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("accept") + "  SELECT"
                              : "ENTER  SELECT"
                        color: view.accent
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("back") + "  CANCEL"
                              : "ESC  CANCEL"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                }
            }
        }
    }

    Rectangle {
        id: couchOverlay
        anchors.fill: parent
        z: 50
        visible: view.overlayOpen
        color: view.withAlpha(view.background, 0.91)

        Loader {
            id: nativeDetails
            anchors.fill: parent
            active: view.overlayOpen && view.overlayMode === "details"
            visible: active
            sourceComponent: CouchDetailsPage {
                details: view.details
                gameTitle: view.selectedTitle
                platform: view.selectedPlatform
                coverUrl: view.coverUrl
                backgroundUrl: view.heroUrl
                logoUrl: { view.library.media_revision; return view.library.exact_artwork_url(view.selectedMediaId, "clear-logo") }
                primaryAction: detailsPrimary.label
                primaryHint: detailsPrimary.hint
                primaryKind: detailsPrimary.kind
                primaryEnabled: detailsPrimary.enabled
                primaryProgress: detailsPrimary.progress
                favorite: view.favorite
                ready: view.detailsCurrent && !view.details.loading
                background: view.background; panel: view.panel
                ink: view.ink; muted: view.muted; accent: view.accentCool
                onCloseRequested: view.closeOverlay()
                onPrimaryRequested: detailsPrimary.activate()
                onFavoriteRequested: view.activateAction(2)
                onVersionsRequested: view.openVariantWheel()
                onManageRequested: section => view.manageGameRequested(section)
            }
        }

        Rectangle {
            id: overlayPanel
            visible: view.overlayMode === "menu"
            anchors.centerIn: parent
            width: Math.min(1180, parent.width - 120)
            height: Math.min(790, parent.height - 110)
            radius: Math.min(32, view.cardRadius + 8)
            color: view.withAlpha(view.panel, 0.96)
            border.color: view.withAlpha(view.muted, 0.56)
            border.width: 1
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 350
                color: view.withAlpha(view.background, 0.72)

                Rectangle {
                    id: overlayCover
                    anchors.top: parent.top
                    anchors.topMargin: 42
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220
                    height: 304
                    radius: view.cardRadius
                    color: view.accentFor(view.selectedTitle)
                    border.color: view.withAlpha(view.ink, 0.55)
                    clip: true
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.lighter(overlayCover.color, 1.18)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.darker(overlayCover.color, 1.62)
                        }
                    }
                    Image {
                        id: overlayCoverImage
                        anchors.fill: parent
                        anchors.margins: 2
                        source: view.overlayOpen && view.overlayMode === "menu" ? view.coverUrl : ""
                        asynchronous: true
                        cache: true
                        mipmap: true
                        autoTransform: true
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 440
                        sourceSize.height: 608
                        opacity: status === Image.Ready ? 1 : 0
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: overlayCoverImage.status !== Image.Ready
                        text: view.selectedTitle.length > 0
                              ? view.selectedTitle.charAt(0).toUpperCase() : "L"
                        color: view.withAlpha(view.ink, 0.87)
                        font.pixelSize: 82
                        font.weight: Font.Black
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: overlayCover.bottom
                    anchors.topMargin: 28
                    anchors.margins: 34
                    spacing: 10

                    Text {
                        width: parent.width
                        text: view.selectedTitle
                        color: view.ink
                        font.pixelSize: 27
                        font.weight: Font.Black
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: view.selectedPlatform.toUpperCase()
                        color: view.muted
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        width: overlayStateText.implicitWidth + 20
                        height: 28
                        radius: Math.max(7, view.cardRadius - 7)
                        color: view.details.can_launch ? view.withAlpha(view.playGreen, 0.22)
                               : view.selectedLocal ? view.withAlpha(view.accentCool, 0.22)
                               : view.selectedDownloadable ? view.withAlpha(view.accent, 0.22)
                                                           : view.withAlpha(view.panelRaised, 0.66)
                        border.color: view.details.can_launch ? view.playGreen
                                      : view.selectedLocal ? view.accentCool
                                      : view.selectedDownloadable ? view.accent
                                                                  : view.withAlpha(view.muted, 0.54)
                        Text {
                            id: overlayStateText
                            anchors.centerIn: parent
                            text: view.details.can_launch ? "READY TO PLAY"
                                  : view.selectedLocal ? "SETUP REQUIRED"
                                  : view.selectedDownloadable ? "MINERVA AVAILABLE"
                                    : "CATALOG RECORD"
                            color: view.details.can_launch ? view.playGreen
                                   : view.selectedLocal ? view.accentCool
                                   : view.selectedDownloadable ? view.accent : view.muted
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }
                    }
                    Text {
                        width: parent.width
                        visible: view.details.emulator_name.length > 0
                        text: view.details.emulator_name
                        color: view.muted
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                id: overlayContent
                anchors.left: parent.left
                anchors.leftMargin: 350
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Row {
                    id: overlayHeader
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.right: parent.right
                    anchors.rightMargin: 30
                    anchors.top: parent.top
                    anchors.topMargin: 30
                    height: 44
                    spacing: 14

                    Text {
                        width: Math.max(0, parent.width - overlayClose.width - parent.spacing)
                        anchors.verticalCenter: parent.verticalCenter
                        text: view.overlayMode === "details"
                              ? "GAME DETAILS" : "GAME MENU"
                        color: view.ink
                        font.pixelSize: 18
                        font.weight: Font.Black
                        font.letterSpacing: 1.2
                    }
                    Rectangle {
                        id: overlayClose
                        width: 42
                        height: 42
                        radius: Math.max(8, view.cardRadius - 4)
                        color: overlayCloseHover.hovered
                               ? view.withAlpha(view.panelRaised, 0.9)
                               : view.withAlpha(view.panelRaised, 0.62)
                        border.color: overlayCloseHover.hovered ? view.accent
                                                               : view.withAlpha(view.muted, 0.54)
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: view.ink
                            font.pixelSize: 22
                        }
                        HoverHandler { id: overlayCloseHover }
                        TapHandler { onTapped: view.closeOverlay() }
                    }
                }

                Row {
                    id: overlayTabs
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.top: overlayHeader.bottom
                    anchors.topMargin: 12
                    spacing: 10

                    Repeater {
                        model: ["DETAILS", "GAME MENU"]
                        delegate: Rectangle {
                            id: overlayTab
                            required property int index
                            required property string modelData
                            property bool selected: view.overlayMode
                                                    === (index === 0 ? "details" : "menu")
                            width: tabText.implicitWidth + 28
                            height: 38
                            radius: Math.max(8, view.cardRadius - 5)
                            color: selected ? view.withAlpha(view.accent, 0.18)
                                            : view.withAlpha(view.panelRaised, 0.58)
                            border.color: selected ? view.accent
                                                   : view.withAlpha(view.muted, 0.44)
                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: overlayTab.modelData
                                color: overlayTab.selected ? view.ink : view.muted
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            TapHandler {
                                onTapped: {
                                    view.overlayMode = overlayTab.index === 0
                                                       ? "details" : "menu"
                                    if (view.overlayMode === "details")
                                        detailsScroller.contentY = 0
                                    view.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                Item {
                    id: overlayBody
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.right: parent.right
                    anchors.rightMargin: 38
                    anchors.top: overlayTabs.bottom
                    anchors.topMargin: 22
                    anchors.bottom: overlayHelp.top
                    anchors.bottomMargin: 18

                    MomentumFlickable {
                        id: detailsScroller
                        anchors.fill: parent
                        visible: view.overlayMode === "details"
                        clip: true
                        contentWidth: width
                        contentHeight: detailsContent.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: detailsContent
                            width: detailsScroller.width - 12
                            spacing: 18

                            Text {
                                width: parent.width
                                text: view.details.loading
                                      ? "Loading the exact game record…"
                                      : view.details.description.length > 0
                                        ? view.details.description
                                        : "No description is available for this exact release."
                                color: view.withAlpha(view.ink, 0.88)
                                font.pixelSize: 15
                                lineHeight: 1.35
                                wrapMode: Text.WordWrap
                            }

                            Grid {
                                width: parent.width
                                columns: 2
                                columnSpacing: 12
                                rowSpacing: 12

                                Repeater {
                                    model: [
                                        { label: "RELEASED", value: view.details.release_date },
                                        { label: "GENRE", value: view.details.genre },
                                        { label: "DEVELOPER", value: view.details.developer },
                                        { label: "PUBLISHER", value: view.details.publisher },
                                        { label: "PLAYERS", value: view.details.players },
                                        { label: "CO-OP", value: view.details.cooperative === "yes"
                                                               ? "Supported"
                                                               : view.details.cooperative === "no"
                                                                 ? "Not supported" : "" },
                                        { label: "RATING", value: view.details.rating.length > 0
                                                                  ? "★ " + view.details.rating
                                                                    + (view.details.rating_count > 0
                                                                       ? " · " + view.details.rating_count.toLocaleString(Qt.locale(), "f", 0)
                                                                         + " ratings" : "") : "" },
                                        { label: "AGE RATING", value: view.details.esrb },
                                        { label: "RELEASE TYPE", value: view.details.release_type },
                                        { label: "SERIES", value: view.details.series },
                                        { label: "REGION", value: view.details.region },
                                        { label: "VERSION", value: view.details.version },
                                        { label: "PLAY MODE", value: view.details.play_mode },
                                        { label: "RELEASE STATUS", value: view.details.release_status },
                                        { label: "METADATA", value: view.details.metadata_source }
                                    ]
                                    delegate: Rectangle {
                                        id: factCard
                                        required property var modelData
                                        visible: String(modelData.value).length > 0
                                        width: (detailsContent.width - 12) / 2
                                        height: visible ? 66 : 0
                                        radius: Math.max(8, view.cardRadius - 4)
                                        color: view.withAlpha(view.panelRaised, 0.4)
                                        border.color: view.withAlpha(view.muted, 0.35)
                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 5
                                            Text {
                                                text: factCard.modelData.label
                                                color: view.muted
                                                font.pixelSize: 8
                                                font.weight: Font.Bold
                                                font.letterSpacing: 1
                                            }
                                            Text {
                                                width: parent.width
                                                text: factCard.modelData.value
                                                color: view.ink
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: activityContent.implicitHeight + 28
                                radius: Math.max(9, view.cardRadius - 2)
                                color: view.withAlpha(view.panelRaised, 0.4)
                                border.color: view.withAlpha(view.muted, 0.35)
                                Column {
                                    id: activityContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 9
                                    Text {
                                        text: "YOUR ACTIVITY"
                                        color: view.accent
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        width: parent.width
                                        text: view.details.activity_visible
                                              ? view.details.play_count + " launches  ·  "
                                                + view.details.play_time + "  ·  "
                                                + view.details.completion_state.split("-").join(" ").toUpperCase()
                                              : "No play activity has been recorded for this game."
                                        color: view.ink
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        visible: view.details.last_played.length > 0
                                        text: "Last played " + view.details.last_played
                                        color: view.muted
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                visible: view.details.notes.length > 0
                                height: visible ? notesContent.implicitHeight + 28 : 0
                                radius: Math.max(9, view.cardRadius - 2)
                                color: view.withAlpha(view.panelRaised, 0.4)
                                border.color: view.withAlpha(view.muted, 0.35)
                                Column {
                                    id: notesContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 8
                                    Text {
                                        text: "NOTES"
                                        color: view.accent
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        width: parent.width
                                        text: view.details.notes
                                        color: view.ink
                                        font.pixelSize: 12
                                        lineHeight: 1.25
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                visible: view.details.tag_count > 0
                                height: visible ? childrenRect.height : 0
                                spacing: 8
                                Repeater {
                                    model: view.details.tag_count
                                    delegate: Rectangle {
                                        id: overlayTag
                                        required property int index
                                        width: overlayTagText.implicitWidth + 20
                                        height: 28
                                        radius: Math.max(7, view.cardRadius - 7)
                                        color: view.withAlpha(view.accentCool, 0.16)
                                        border.color: view.accentCool
                                        Text {
                                            id: overlayTagText
                                            anchors.centerIn: parent
                                            text: view.details.tag_at(overlayTag.index).toUpperCase()
                                            color: view.accentCool
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.6
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: view.details.firmware_rule_count > 0
                                         || view.details.launch_status.length > 0
                                text: [view.details.launch_status,
                                       view.details.firmware_summary]
                                      .filter(value => value.length > 0).join("\n")
                                color: view.details.can_launch ? view.accentCool : view.muted
                                font.pixelSize: 11
                                lineHeight: 1.3
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: 3
                            radius: 2
                            visible: detailsScroller.contentHeight > detailsScroller.height
                            height: visible ? Math.max(36, detailsScroller.height
                                                      * detailsScroller.height
                                                      / detailsScroller.contentHeight) : 0
                            y: visible ? detailsScroller.contentY
                                         * (detailsScroller.height - height)
                                         / Math.max(1, detailsScroller.contentHeight
                                                    - detailsScroller.height) : 0
                            color: view.accent
                        }
                    }

                    Column {
                        id: gameMenu
                        anchors.fill: parent
                        visible: view.overlayMode === "menu"
                        spacing: 12

                        Text {
                            width: parent.width
                            text: "Choose what to do with this exact release. Download and management actions hand off to the complete desktop tools without losing selection."
                            color: view.muted
                            font.pixelSize: 13
                            lineHeight: 1.3
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: view.menuActionCount
                            delegate: Rectangle {
                                id: menuAction
                                required property int index
                                property bool selected: view.menuActionIndex === index
                                readonly property bool playAction: index === 0
                                                                   && view.primaryAction === "Play"
                                width: gameMenu.width
                                height: 88
                                radius: Math.max(9, view.cardRadius - 2)
                                color: selected ? view.withAlpha(playAction ? view.playGreen : view.accent, 0.2)
                                       : menuHover.hovered
                                         ? view.withAlpha(view.panelRaised, 0.72)
                                         : view.withAlpha(view.panelRaised, 0.4)
                                border.color: selected ? (playAction ? view.playGreen : view.accent)
                                                       : view.withAlpha(view.muted, 0.35)
                                border.width: selected ? 2 : 1
                                opacity: view.menuActionEnabled(menuAction.index) ? 1 : 0.46
                                scale: selected ? 1.012 : 1
                                Behavior on scale { NumberAnimation { duration: 90 } }
                                Behavior on opacity { NumberAnimation { duration: 110 } }

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: menuGlyph.left
                                    anchors.rightMargin: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 20
                                    spacing: 7
                                    Text {
                                        width: parent.width
                                        text: view.menuActionLabel(menuAction.index)
                                        color: menuAction.playAction ? view.playGreen
                                               : menuAction.index === 0 ? view.accent : view.ink
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.6
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: view.menuActionDescription(menuAction.index)
                                        color: view.muted
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    id: menuGlyph
                                    anchors.right: parent.right
                                    anchors.rightMargin: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: menuAction.index === 0 ? "▶"
                                          : menuAction.index === 1
                                            ? (view.favorite ? "★" : "☆")
                                          : menuAction.index === 2 ? "↗"
                                          : menuAction.index === 3 ? "◈"
                                          : menuAction.index === 4 ? "◌"
                                          : menuAction.index === 5 ? "▦"
                                          : menuAction.index === 6 ? "♪" : "×"
                                    color: menuAction.selected
                                           ? (menuAction.playAction ? view.playGreen : view.accent)
                                           : view.muted
                                    font.pixelSize: menuAction.index === 1 ? 24 : 18
                                    font.weight: Font.Bold
                                }
                                HoverHandler { id: menuHover }
                                TapHandler {
                                    enabled: view.menuActionEnabled(menuAction.index)
                                    onTapped: {
                                        view.menuActionIndex = menuAction.index
                                        view.activateMenuAction(menuAction.index)
                                        view.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    id: overlayHelp
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.right: parent.right
                    anchors.rightMargin: 38
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 24
                    height: 24
                    spacing: 20

                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("page_left") + " / "
                                + view.gamepad.button_label("page_right") + "  SWITCH PANEL"
                              : "← →  SWITCH PANEL"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("accept") + "  SELECT"
                              : "ENTER  SELECT"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }
                    Item { width: Math.max(0, parent.width - 480); height: 1 }
                    Text {
                        text: view.gamepad.connected_count > 0
                              ? view.gamepad.button_label("back") + "  CLOSE"
                              : "ESC  CLOSE"
                        color: view.muted
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: attractProgressAnimation
        target: view
        property: "attractProgress"
        from: 0
        to: 1
        duration: Math.max(5000, view.library.couch_attract_cycle_seconds * 1000)
    }

    Timer {
        id: attractIdleTimer
        interval: view.attractProbeEnabled
                  ? 350
                  : Math.max(30, view.library.couch_attract_idle_seconds) * 1000
        repeat: false
        running: view.active && view.inputEnabled
                 && (view.library.couch_attract_enabled
                     || view.attractProbeEnabled)
                 && !view.attractOpen
                 && !view.searchOpen
                 && !view.overlayOpen
                 && !view.platformWheelOpen
                 && !view.collectionWheelOpen
                 && shelf.count > 0
        onTriggered: view.startAttractMode("idle")
    }

    Timer {
        id: attractCycleTimer
        interval: Math.max(5, view.library.couch_attract_cycle_seconds) * 1000
        repeat: false
        running: view.active && view.attractOpen && shelf.count > 0
        onTriggered: view.moveAttract(1)
    }

    Timer {
        id: entrySound
        interval: 280
        onTriggered: if (view.active) feedback.play("enter")
    }
    Timer {
        id: selectionDelay
        interval: 320
        repeat: false
        onTriggered: {
            if (view.active)
                view.loadCurrentGame()
        }
    }

    Timer {
        id: previewRefresh
        interval: 240
        onTriggered: if (view.active && view.selectedGameId) view.library.request_couch_preview(view.selectedGameId)
    }

    Timer {
        id: selectionRetry
        interval: 40
        repeat: false
        onTriggered: {
            if (!view.active)
                return
            if (shelf.count > 0) {
                if (shelf.currentIndex < 0) {
                    const preferredRow = view.library.row_for_game(
                                               view.preferredGameId)
                    shelf.currentIndex = preferredRow >= 0
                                       && preferredRow < shelf.count
                                       ? preferredRow : 0
                    shelf.positionViewAtIndex(shelf.currentIndex,
                                              ListView.Center)
                }
                view.loadCurrentGame()
            } else if (view.library.filtered_count > 0) {
                selectionRetry.restart()
            }
        }
    }

    Connections {
        target: view.library
        function onLoadingChanged() {
            // The fast startup catalog may already be browsing while the full
            // catalog arrives. Its model reset changes row numbers, not the
            // user's chosen game. Pin the identity before that reset begins.
            if (!view.library.loading && view.active && !entrySelection.pending
                    && view.selectedGameId.length > 0)
                entrySelection.begin(view.selectedGameId, view.library.current_platform)
        }
        function onFiltered_countChanged() {
            if (entrySelection.pending) { entrySelection.reconcile(); return }
            if (shelf.count <= 0) {
                view.stopAttractMode()
                shelf.currentIndex = -1
                view.selectedGameId = ""
                view.selectedDatabaseId = 0
                view.selectedMediaId = 0
                view.selectedTitle = ""
                return
            }
            shelf.currentIndex = Math.max(0, Math.min(shelf.currentIndex,
                                                      shelf.count - 1))
            if (view.active)
                selectionDelay.restart()
        }
        function onMedia_loadingChanged() {
            if (view.active && !view.library.media_loading) {
                view.loadedGameId = ""
                selectionDelay.restart()
            }
        }
        function onCollection_revisionChanged() {
            if (view.collectionWheelOpen) {
                view.collectionWheelIndex = view.library.collection_count > 0
                        ? Math.max(0, Math.min(view.collectionWheelIndex,
                                             view.library.collection_count - 1))
                        : 0
                collectionWheel.currentIndex = view.library.collection_count > 0
                        ? view.collectionWheelIndex : -1
            }
            view.syncCategory()
        }
    }

    Timer {
        id: sc2NavigationDelay
        interval: 40
        repeat: false
        onTriggered: {
            const action = view.pendingSc2Actions.shift()
            if (action && view.active
                    && !view.gamepad.keyboard_handled_recently(action))
                view.handleNavigation(action)
            if (view.pendingSc2Actions.length > 0)
                restart()
        }
    }

    Connections {
        target: view.gamepad
        function onNavigation_revisionChanged() {
            if (!view.active || !view.inputEnabled) return
            const action = view.gamepad.navigation_action
            if (view.gamepad.active_device !== "Steam Controller 2 (2026)") {
                view.handleNavigation(action)
                return
            }
            view.pendingSc2Actions.push(action)
            if (!sc2NavigationDelay.running)
                sc2NavigationDelay.start()
        }
    }
}
