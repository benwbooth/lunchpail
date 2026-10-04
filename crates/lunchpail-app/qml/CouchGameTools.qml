pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Column {
    id: tools
    objectName: "couchGameTools"
    required property var details
    required property var mods
    required property var patches
    required property var achievements
    required property var saveSync
    required property var library
    required property var emuMovies
    required property var soundtrackPlayer
    property string section: "display"
    property var pickPatchFile: function() { return "" }
    property var pickCheatFile: function() { return "" }
    property var pickCheatExport: function() { return "" }
    readonly property bool locked: details.launch_busy || details.game_running
    readonly property bool retroarch: (details.emulator_name || "").toLowerCase().includes("retroarch")
    readonly property var preview: {
        try {
            const record = JSON.parse(library.couch_preview_json || "{}")
            return record.game_id === details.game_id ? record : {}
        } catch (_) { return {} }
    }
    signal achievementsSetupRequested()
    signal bezelPickerRequested()
    signal removeInstallationRequested()
    signal manageIdentityRequested()
    signal torrentRequested()
    signal reviewCandidateRequested(int index)
    signal manageRequested(string section)
    signal relatedRequested(int index)
    signal artworkRequested(url source, string provider)
    signal findArtworkRequested(string kind)
    signal tagRequested(string tag)
    spacing: 20

    component Heading: Text {
        width: parent.width; color: "#f4f7fb"; font.pixelSize: 22
        font.weight: Font.DemiBold; wrapMode: Text.WordWrap
    }
    component Copy: Text {
        width: parent.width; color: "#a7b4c4"; font.pixelSize: 17
        wrapMode: Text.WordWrap; lineHeight: 1.25
    }
    component Action: LbButton {
        width: parent.width; implicitHeight: 50
        contentItem: LbButtonLabel { control: parent; pixelSize: 17 }
    }
    component Choice: LbComboBox {
        id: combo
        font.pixelSize: 17
        contentItem: Text {
            text: combo.displayText; font: combo.font
            color: combo.enabled ? "#f4f7fb" : "#8d99aa"
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
        delegate: ItemDelegate {
            required property int index
            width: combo.popup.width; implicitHeight: 48
            text: combo.textAt(index); font.pixelSize: 17
            highlighted: combo.highlightedIndex === index
        }
    }

    Loader {
        width: parent.width; active: tools.section === "artwork"; visible: active
        sourceComponent: Column {
            id: gallery
            objectName: "couchArtworkGallery"
            property var kinds: [{key:"box-front", label:"Front covers"}, {key:"box-back", label:"Back covers"}, {key:"box-3d", label:"3D artwork"}, {key:"fanart", label:"Backgrounds"}, {key:"screenshot", label:"Screenshots"}, {key:"title-screen", label:"Title screens"}, {key:"clear-logo", label:"Wheel logos"}]
            property string kind: kinds[artworkKind.currentIndex].key
            property double mediaId: tools.library.media_id_for_game(tools.details.game_id)
            property var images: { tools.library.media_revision; return JSON.parse(tools.library.exact_artwork_candidates_json(mediaId, kind)) }
            property int count: images.length
            spacing: 20
            Heading { text: "Artwork gallery" }
            Choice {
                id: artworkKind; objectName: "couchArtworkKind"; width: parent.width; implicitHeight: 54
                model: gallery.kinds; textRole: "label"
            }
            Action { text: "Find or replace " + gallery.kinds[artworkKind.currentIndex].label.toLowerCase(); onClicked: tools.findArtworkRequested(gallery.kind) }
            Action { text: "Explore the 3D box"; onClicked: tools.manageRequested("box3d") }
            Copy { visible: gallery.count === 0; text: "No cached artwork of this type. Find media above to choose an image." }
            Flow {
                width: parent.width; spacing: 16
                Repeater {
                    model: gallery.count
                    delegate: LbButton {
                        id: artworkTile
                        required property int index
                        width: (parent.width - 16) / 2; height: 310
                        property url artwork: gallery.images[index]?.url || ""
                        property string provider: gallery.images[index]?.source || ""
                        text: provider
                        contentItem: Column {
                            spacing: 12
                            Image { width: parent.width; height: 250; source: artworkTile.artwork; asynchronous: true; fillMode: Image.PreserveAspectFit; sourceSize: Qt.size(720, 500) }
                            Text { width: parent.width; text: artworkTile.provider; color: "#d7e2ef"; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter }
                        }
                        onClicked: tools.artworkRequested(artwork, provider)
                    }
                }
            }
        }
    }

    Loader {
        width: parent.width; active: tools.section === "launch"; visible: active
        sourceComponent: Column {
            spacing: 18
            Heading { text: "How this game plays" }
            Copy { text: tools.details.launch_status || "Choose an emulator and save a default for this game or its system." }
            Choice {
                width: parent.width; implicitHeight: 54
                enabled: !tools.locked && !tools.details.launch_discovery_busy
                model: tools.details.emulator_option_count
                currentIndex: tools.details.selected_emulator_option
                displayText: currentIndex >= 0 ? tools.details.emulator_option_label_at(currentIndex) : "No compatible emulator"
                delegate: ItemDelegate {
                    required property int index
                    width: parent.width; implicitHeight: 48
                    text: tools.details.emulator_option_label_at(index); font.pixelSize: 17
                }
                onActivated: index => tools.details.select_emulator_option(index)
            }
            RowLayout {
                width: parent.width
                LbButton { Layout.fillWidth: true; implicitHeight: 50; text: "Use for this game"; enabled: !tools.locked && tools.details.selected_emulator_option >= 0; onClicked: tools.details.save_game_emulator_preference() }
                LbButton { Layout.fillWidth: true; implicitHeight: 50; text: "Use for this system"; enabled: !tools.locked && tools.details.selected_emulator_option >= 0; onClicked: tools.details.save_platform_emulator_preference() }
            }
            Action {
                text: "Clear " + tools.details.emulator_preference_scope + " default"
                visible: ["game", "platform"].includes(tools.details.emulator_preference_scope)
                enabled: !tools.locked
                onClicked: {
                    if (tools.details.emulator_preference_scope === "game") tools.details.clear_game_emulator_preference()
                    else tools.details.clear_platform_emulator_preference()
                }
            }
            RowLayout {
                width: parent.width
                LbButton { Layout.fillWidth: true; implicitHeight: 50; text: "Manage emulators"; onClicked: tools.manageRequested("emulators") }
                LbButton { Layout.fillWidth: true; implicitHeight: 50; text: "Refresh"; enabled: !tools.locked && !tools.details.launch_discovery_busy; onClicked: tools.details.refresh_emulators() }
            }
            Action { text: "Launch profile & arguments"; enabled: !tools.locked; onClicked: tools.manageRequested("launch-profile") }
            Action { text: tools.details.firmware_setup_label || "BIOS & firmware"; onClicked: tools.manageRequested("firmware") }
            LbCheckBox {
                font.pixelSize: 17
                width: parent.width; implicitHeight: 50; text: "Launch with GameBuddy"
                checked: tools.details.gamebuddy_enabled; enabled: !tools.locked
                onClicked: tools.details.configure_gamebuddy(checked, tools.details.gamebuddy_executable)
            }
            LbTextField {
                font.pixelSize: 17
                width: parent.width; implicitHeight: 50; visible: tools.details.gamebuddy_enabled
                text: tools.details.gamebuddy_executable; placeholderText: "GameBuddy executable (or PATH)"
                enabled: !tools.locked
                onEditingFinished: tools.details.configure_gamebuddy(tools.details.gamebuddy_enabled, text)
            }
            Column {
                width: parent.width; spacing: 12
                visible: tools.details.preparable || tools.details.prepared || tools.details.prepare_busy
                Heading { text: "PC installation" }
                Copy { text: tools.details.prepared_summary || tools.details.preparation_file || "Prepare this archive in Lunchpail’s private cache before playing." }
                Action { text: tools.details.prepare_busy ? "Cancel preparation" : tools.details.prepared ? "Verify & refresh install" : "Prepare game"; enabled: !tools.locked && (tools.details.preparable || tools.details.prepare_busy); onClicked: tools.details.prepare_busy ? tools.details.cancel_preparation() : tools.details.prepare_game() }
            }
        }
    }
    Loader {
        width: parent.width; active: tools.section === "themes"; visible: active
        sourceComponent: Column {
            spacing: 22
            Heading { text: "HyperSpin video theme" }
            Copy { text: "Pre-rendered game animations from EmuMovies. These are separate from gameplay clips, and not every game has one. A supporting EmuMovies account is required for FTP video downloads." }
            Action { text: "Watch cached theme"; visible: !!tools.preview.theme_video_url; onClicked: tools.manageRequested("theme-video") }
            Action {
                text: tools.emuMovies.busy && tools.emuMovies.last_media_kind === "theme-video" ? "Downloading theme…" : tools.emuMovies.credentials_saved ? "Find HyperSpin video theme" : "Connect EmuMovies"
                enabled: !tools.emuMovies.busy
                onClicked: {
                    if (tools.emuMovies.credentials_saved)
                        tools.emuMovies.download_theme_video(tools.details.game_id, tools.library.database_id_for_game(tools.details.game_id), tools.details.title, tools.details.platform)
                    else tools.manageRequested("emumovies")
                }
            }
            InlineProgressBar { width: parent.width; height: 8; visible: tools.emuMovies.busy; from: 0; to: 100; value: Math.max(0, tools.emuMovies.transfer_progress) }
            Copy { text: tools.emuMovies.message || "" }
            Action { text: "Cancel EmuMovies transfer"; visible: tools.emuMovies.busy; enabled: !tools.emuMovies.cancel_requested; onClicked: tools.emuMovies.cancel() }
            Heading { text: "System wheel artwork" }
            Copy { text: "EmuMovies logo packs can include the system logo as well as game logos. The platform wheel uses these separately from game artwork." }
            Image {
                width: parent.width; height: status === Image.Ready ? 100 : 0
                source: { tools.emuMovies.published_revision; return tools.library.platform_media_url(tools.details.platform, "clear-logo") }
                fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize: Qt.size(640, 200)
            }
            Action {
                text: "Get " + tools.details.platform + " wheel logo"; enabled: !tools.emuMovies.busy
                onClicked: tools.emuMovies.credentials_saved ? tools.emuMovies.download_platform_media(tools.details.platform, "clear-logo") : tools.manageRequested("emumovies")
            }
            Action {
                text: "Get platform video theme"; enabled: !tools.emuMovies.busy
                onClicked: tools.emuMovies.credentials_saved ? tools.emuMovies.download_platform_media(tools.details.platform, "video") : tools.manageRequested("emumovies")
            }
        }
    }
    Loader {
        width: parent.width; active: tools.section === "media"; visible: active
        sourceComponent: Column {
            spacing: 22
            Heading { text: "Video & artwork" }
            Action { text: tools.details.video_available ? "Watch gameplay video" : "No gameplay video cached"; enabled: tools.details.video_available; onClicked: tools.manageRequested("video") }
            Action { text: "Browse artwork gallery"; onClicked: tools.manageRequested("artwork") }
            Action { text: "Find or replace artwork"; onClicked: tools.manageRequested("find-media") }
            Action { text: "HyperSpin themes & system media"; onClicked: tools.manageRequested("themes") }
            Heading { text: "Game manual" }
            Copy { text: tools.details.manual_available ? "Your cached manual is ready to open." : tools.details.manual_download_message || "Find a manual from Minerva or EmuMovies." }
            Action {
                text: tools.details.manual_available ? "Read manual" : tools.details.manual_transfer_active ? "Cancel manual download" : "Find manual · Minerva"
                enabled: !tools.details.manual_action_busy
                onClicked: {
                    if (tools.details.manual_available) Qt.openUrlExternally(tools.details.manual_url)
                    else if (tools.details.manual_transfer_active) tools.details.cancel_manual_download()
                    else tools.details.download_manual()
                }
            }
            InlineProgressBar { width: parent.width; height: 8; visible: tools.details.manual_transfer_active; from: 0; to: 100; value: tools.details.manual_download_progress }
            Action {
                text: tools.emuMovies.credentials_saved ? "Find manual · EmuMovies" : "Connect EmuMovies"
                enabled: !tools.emuMovies.busy && !tools.details.manual_action_busy
                onClicked: {
                    if (tools.emuMovies.credentials_saved)
                        tools.emuMovies.download_manual(tools.details.game_id, tools.library.database_id_for_game(tools.details.game_id), tools.details.title, tools.details.platform)
                    else tools.manageRequested("emumovies")
                }
            }
            Heading { text: "Soundtrack" }
            Item {
                width: parent.width
                height: soundtrack.height * soundtrack.scale
                GameSoundtrackCard {
                    id: soundtrack
                    width: parent.width / scale; scale: 1.5; transformOrigin: Item.TopLeft
                    detailsModel: tools.details; emuMoviesModel: tools.emuMovies; mediaPlayer: tools.soundtrackPlayer
                    gameId: tools.details.game_id; databaseId: tools.library.database_id_for_game(tools.details.game_id)
                    gameTitle: tools.details.title; platform: tools.details.platform
                    onSettingsRequested: tools.manageRequested("emumovies")
                }
            }
            Copy { text: tools.details.media_message || "" }
        }
    }
    Loader {
        width: parent.width; active: tools.section === "activity"; visible: active
        sourceComponent: Column {
            spacing: 22
            Heading { text: tools.details.play_count + " plays · " + tools.details.play_time }
            Copy { text: tools.details.last_played ? "Last played " + tools.details.last_played : "You haven’t played this game yet." }
            Heading { text: "Completion" }
            Choice {
                id: completion
                width: parent.width; implicitHeight: 54
                enabled: !tools.details.activity_busy
                textRole: "label"; valueRole: "key"
                model: [{key:"not_started", label:"Not started"}, {key:"in_progress", label:"In progress"}, {key:"completed", label:"Completed"}, {key:"on_hold", label:"On hold"}, {key:"abandoned", label:"Abandoned"}]
                function sync() { currentIndex = Math.max(0, indexOfValue(tools.details.completion_state)) }
                Component.onCompleted: sync()
                Connections { target: tools.details; function onCompletion_stateChanged() { completion.sync() } }
                onActivated: tools.details.save_completion_state(currentValue)
            }
            Action { text: "Play-session history (" + tools.details.session_count + ")"; enabled: tools.details.session_count > 0; onClicked: tools.manageRequested("sessions") }
            Heading { text: "My notes" }
            Copy { text: tools.details.notes || "Add a reminder, a secret, or your next objective." }
            Action { text: "Edit notes & rating"; onClicked: tools.manageRequested("metadata") }
        }
    }
    Loader {
        width: parent.width; active: tools.section === "collections"; visible: active
        sourceComponent: Column {
            spacing: 12
            Copy { text: "Manual collections can be changed here. Automatic collections follow their saved rules." }
            Repeater {
                model: tools.library.collection_count
                delegate: LbCheckBox {
                    font.pixelSize: 17
                    required property int index
                    width: parent.width; implicitHeight: 56
                    property int revision: tools.library.collection_revision
                    text: { revision; return tools.library.collection_name_at(index) + (tools.library.collection_kind_at(index) === "smart" ? " · Automatic" : "") }
                    checked: { revision; return tools.library.collection_contains(tools.library.collection_id_at(index), tools.details.game_id) }
                    enabled: !tools.library.collection_busy && tools.library.collection_kind_at(index) === "manual"
                    onClicked: tools.library.set_collection_membership(tools.library.collection_id_at(index), tools.details.game_id, checked)
                }
            }
            Action { text: "Create a collection"; onClicked: tools.manageRequested("new-collection") }
        }
    }
    Loader {
        width: parent.width; active: tools.section === "related"; visible: active
        sourceComponent: Column {
            spacing: 14
            Copy { text: tools.details.related_game_message || "Related games from your catalog" }
            Repeater {
                model: tools.details.related_game_count
                delegate: Action {
                    required property int index
                    text: tools.details.related_game_title_at(index) + " · " + tools.details.related_game_platform_at(index)
                    onClicked: tools.relatedRequested(index)
                }
            }
        }
    }
    Loader {
        width: parent.width; active: tools.section === "catalog"; visible: active
        sourceComponent: Column {
            spacing: 20
            Heading { text: "Catalog information" }
            Copy { text: tools.details.metadata_source ? "Source: " + tools.details.metadata_source : "No metadata source recorded" }
            Repeater {
                model: tools.details.custom_field_count
                delegate: Column {
                    required property int index
                    width: parent.width; spacing: 5
                    property int revision: tools.details.custom_field_revision
                    Heading { text: { parent.revision; return tools.details.custom_field_name_at(parent.index) } }
                    Copy { text: { parent.revision; return tools.details.custom_field_value_at(parent.index) } }
                }
            }
            Heading { text: "Tags" }
            Copy { visible: tools.details.tag_count === 0; text: "No tags yet" }
            Flow {
                width: parent.width; spacing: 12
                Repeater {
                    model: tools.details.tag_count
                    delegate: LbButton {
                        required property int index
                        height: 48
                        text: { tools.details.tag_revision; return tools.details.tag_at(index) }
                        contentItem: LbButtonLabel { control: parent; pixelSize: 17 }
                        onClicked: tools.tagRequested(text)
                    }
                }
            }
            Repeater {
                model: tools.details.alternate_title_count
                delegate: Copy {
                    required property int index
                    text: tools.details.alternate_title_at(index) + " · " + tools.details.alternate_title_region_at(index)
                }
            }
            Copy { visible: tools.details.rating_count > 0; text: "Catalog rating: " + tools.details.rating + " from " + tools.details.rating_count + " votes" }
            Repeater {
                model: [{label:"Catalog video", url:tools.details.catalog_video_url}, {label:"Wikipedia", url:tools.details.wikipedia_url}, {label:"Steam store", url:tools.details.steam_store_url}]
                delegate: Action {
                    required property var modelData
                    text: modelData.label; visible: String(modelData.url || "").length > 0
                    onClicked: Qt.openUrlExternally(modelData.url)
                }
            }
            Action { text: "Edit game information"; onClicked: tools.manageRequested("metadata") }
        }
    }

    Loader {
        width: parent.width
        active: tools.section === "display"
        visible: active
        sourceComponent: Column {
            spacing: 18
            enabled: !tools.locked
            Text { width: parent.width; text: tools.details.display_effective_summary; color: "#a7b4c4"; font.pixelSize: 18; wrapMode: Text.WordWrap }
            RowLayout {
                width: parent.width
                LbButton { Layout.fillWidth: true; implicitHeight: 50; text: "This game"; highlighted: tools.details.display_scope === "game"; onClicked: tools.details.select_display_scope("game") }
                LbButton { Layout.fillWidth: true; implicitHeight: 50; text: "Whole system"; highlighted: tools.details.display_scope === "platform"; onClicked: tools.details.select_display_scope("platform") }
            }
            Repeater {
                model: [
                    {key: "fullscreen", title: "Fullscreen", current: tools.details.display_fullscreen, supported: tools.details.display_fullscreen_supported, inherited: tools.details.display_inherited_fullscreen_label},
                    {key: "shader", title: "Display shader", current: tools.details.display_shader, supported: tools.details.display_shader_supported, inherited: tools.details.display_inherited_shader_label},
                    {key: "bezel", title: "Bezel artwork", current: tools.details.display_bezel, supported: tools.details.display_bezel_supported, inherited: tools.details.display_inherited_bezel_label},
                    {key: "save_states", title: "Save states", current: tools.details.display_save_states, supported: tools.details.display_save_states_supported, inherited: tools.details.display_inherited_save_states_label}
                ]
                delegate: Column {
                    id: setting
                    required property var modelData
                    width: parent.width; spacing: 8; visible: modelData.supported
                    Text { text: setting.modelData.title; color: "#f4f7fb"; font.pixelSize: 20 }
                    Choice {
                        id: choice
                        width: parent.width; implicitHeight: 52
                        textRole: "label"; valueRole: "value"
                        model: {
                            const rev = tools.details.display_revision
                            const items = [{ value: "", label: setting.modelData.inherited }]
                            const key = setting.modelData.key
                            if (key === "fullscreen") return items.concat([{value:"true", label:"Fullscreen"}, {value:"false", label:"Windowed"}])
                            if (key === "save_states") return items.concat([{value:"off", label:"Off"}, {value:"on", label:"Save + resume"}])
                            const shader = key === "shader"
                            if (!shader) items.push({value: "off", label: "Off"})
                            const count = shader ? tools.details.display_shader_preset_count() : tools.details.display_bezel_choice_count()
                            for (let i = 0; i < count; i++) items.push({
                                value: shader ? tools.details.display_shader_preset_id_at(i) : tools.details.display_bezel_choice_id_at(i),
                                label: shader ? tools.details.display_shader_preset_label_at(i) : tools.details.display_bezel_choice_label_at(i)
                            })
                            if (!shader && setting.modelData.current && !items.some(item => item.value === setting.modelData.current))
                                items.push({value: setting.modelData.current, label: tools.details.display_bezel_label()})
                            return items
                        }
                        function sync() { currentIndex = Math.max(0, indexOfValue(setting.modelData.current)) }
                        onModelChanged: sync()
                        Component.onCompleted: sync()
                        Connections { target: setting; function onModelDataChanged() { choice.sync() } }
                        onActivated: tools.details.set_display_setting(setting.modelData.key, currentValue)
                    }
                }
            }
            LbCheckBox {
                font.pixelSize: 17
                width: parent.width
                text: "Translate this game"; checked: tools.details.translation_opted_in
                onClicked: tools.details.save_translation_opt_in(checked)
            }
            Column {
                width: parent.width; spacing: 10; visible: tools.details.arcade_blood_available
                Heading { text: "Arcade blood setting" }
                Choice {
                    width: parent.width; implicitHeight: 54
                    enabled: tools.details.arcade_blood_supported
                    textRole: "label"; valueRole: "value"
                    model: [{value:"game", label:"Use game setting"}, {value:"red", label:"Red blood"}, {value:"censored", label:"Censored blood"}]
                    currentIndex: tools.details.arcade_blood === "red" ? 1 : tools.details.arcade_blood === "censored" ? 2 : 0
                    onActivated: tools.details.save_arcade_blood(currentValue)
                }
                Copy { text: tools.details.arcade_blood_supported ? "Remembered for this game and reapplied after loading a state. Changes apply next launch." : "Requires RetroArch MAME with an arcade (MVS) BIOS." }
            }
            LbButton {
                width: parent.width; implicitHeight: 50
                visible: tools.details.display_bezel_supported
                text: "Choose bezel…"
                onClicked: tools.bezelPickerRequested()
            }
        }
    }
    Loader {
        width: parent.width
        active: tools.section === "mods"
        visible: active
        sourceComponent: Column {
            spacing: 20
            CommunityPatchesPane {
                width: parent.width; backend: tools.patches
                gameId: tools.details.game_id; gameTitle: tools.details.title; platform: tools.details.platform
                romPath: { tools.details.local_file_revision; return tools.details.local_file_path_at(tools.details.selected_local_file) }
                locked: tools.locked; Component.onCompleted: expanded = true
            }
            GameModsPane {
                width: parent.width; backend: tools.mods; gameId: tools.details.game_id
                retroarch: tools.retroarch; locked: tools.locked || tools.patches.applying
                pickPatchFile: tools.pickPatchFile; pickCheatFile: tools.pickCheatFile; pickCheatExport: tools.pickCheatExport
                Component.onCompleted: expanded = true
            }
        }
    }
    Loader {
        width: parent.width
        active: tools.section === "achievements"
        visible: active
        sourceComponent: RetroAchievementsPane {
            backend: tools.achievements; gameId: tools.details.game_id
            retroarch: tools.retroarch; locked: tools.locked
            Component.onCompleted: expanded = true
            onSetupRequested: tools.achievementsSetupRequested()
        }
    }
    Loader {
        width: parent.width
        active: tools.section === "files"
        visible: active
        sourceComponent: Column {
            spacing: 20
            GameFilesCard {
                width: parent.width; visible: tools.details.local_file_count > 0
                height: visible ? implicitHeight : 0
                detailsModel: tools.details
                ink: "#f4f7fb"; muted: "#95a2b6"; line: "#344358"; accent: "#ffb454"; accentCool: "#62dac8"
                onRemoveInstallationRequested: tools.removeInstallationRequested()
                onManageIdentityRequested: tools.manageIdentityRequested()
            }
            GameTorrentSources {
                width: parent.width; detailsModel: tools.details
                installed: tools.details.local; alternativesExpanded: true; showAddSource: true
                onAddSourceRequested: tools.torrentRequested()
                onReviewCandidateRequested: index => tools.reviewCandidateRequested(index)
            }
            GameSaveLocationsCard {
                width: parent.width
                ink: "#f4f7fb"; muted: "#95a2b6"; panel: "#182230"; line: "#344358"
                target: {
                    const changes = [tools.details.detail_revision, tools.details.local_file_revision, tools.details.selected_emulator_option, tools.saveSync.revision]
                    try { return JSON.parse(tools.details.save_sync_target_json()) } catch (_) { return {} }
                }
                backup: {
                    const revision = tools.saveSync.revision
                    try { return JSON.parse(tools.saveSync.backup_location_json(target.emulator_slug || "", target.runtime_platform || "")) } catch (_) { return {} }
                }
                onOpenFolderRequested: folder => Qt.openUrlExternally(folder)
            }
        }
    }
}
