import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "CouchGameTools"
    when: windowShown
    QtObject {
        id: detailsMock
        property string game_id: "test-game"
        property string emulator_name: ""
        property bool launch_busy: false
        property bool game_running: false
        property bool activity_busy: false
        property int play_count: 3
        property string play_time: "1 hour"
        property string last_played: "Yesterday"
        property string completion_state: "in_progress"
        property int session_count: 2
        property string notes: "A note"
        property string metadata_source: "Test catalog"
        property int custom_field_count: 0
        property int custom_field_revision: 0
        property int tag_count: 0
        property int tag_revision: 0
        property int alternate_title_count: 0
        property int rating_count: 0
        property string rating: ""
        property string catalog_video_url: ""
        property string wikipedia_url: ""
        property string steam_store_url: ""
        function save_completion_state(value) { completion_state = value }
    }
    QtObject {
        id: libraryMock
        property string couch_preview_json: "{}"
        property int collection_count: 0
        property int media_revision: 0
        function media_id_for_game(gameId) { return 140 }
        function exact_artwork_candidates_json(mediaId, kind) {
            return JSON.stringify(kind === "box-front" ? [{url: "", source: "Test cover"}] : [])
        }
    }
    Component {
        id: toolsComponent
        Lunchpail.CouchGameTools {
            width: 900; section: "activity"
            details: detailsMock; library: libraryMock
            mods: ({}); patches: ({}); achievements: ({})
            saveSync: ({}); emuMovies: ({}); soundtrackPlayer: ({})
        }
    }
    function init() { failOnWarning(/.*/) }
    function test_gallery_does_not_substitute_covers_for_missing_screenshots() {
        const page = createTemporaryObject(toolsComponent, this, {section: "artwork"})
        verify(page)
        const gallery = findChild(page, "couchArtworkGallery")
        const kind = findChild(page, "couchArtworkKind")
        verify(gallery)
        verify(kind)
        compare(gallery.count, 1)
        kind.currentIndex = 4
        compare(gallery.kind, "screenshot")
        compare(gallery.count, 0)
        kind.currentIndex = 6
        compare(gallery.kind, "clear-logo")
        compare(gallery.count, 0)
        kind.currentIndex = 0
        compare(gallery.count, 1)
    }
    function test_switching_sections_does_not_leave_inactive_loader_space() {
        const page = createTemporaryObject(toolsComponent, this)
        verify(page)
        for (const section of ["activity", "collections", "catalog", "activity", "catalog"]) {
            page.section = section
            wait(40)
            const loaders = Array.from(page.children).filter(child => child.sourceComponent !== undefined)
            const active = loaders.filter(loader => loader.active)
            compare(active.length, 1)
            compare(active[0].y, 0)
            verify(page.height > 0)
            verify(page.height <= active[0].height + 1)
            for (const loader of loaders.filter(loader => !loader.active)) compare(loader.visible, false)
        }
    }
}
