import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "CouchGameBrowser"
    when: windowShown
    visible: true
    width: 1280; height: 720

    Component {
        id: browserComponent
        Lunchpail.CouchGameBrowser {
            width: 1120; height: 540
            background: "#101620"; panel: "#182230"; panelRaised: "#253244"
            ink: "#ffffff"; muted: "#8899aa"; accent: "#ffb454"; accentCool: "#62d9d0"
            cardRadius: 12
            library: ListModel {
                property bool filtering: false
                property int media_revision: 0
                property int favorite_revision: 0
                property int favorite_pending_count: 0
                property var favorites: ({})
                function is_favorite(id) { return favorites[id] === true }
                function favorite_pending(id) { return false }
                function set_favorite(id, favorite) {
                    favorites[id] = favorite
                    favorite_revision++
                }
                function artwork_url(id, kind) { return "" }
                function exact_artwork_url(id, kind) { return "" }
                function request_artwork(id, title, platform, kind) {}
                function request_artwork_for_game(id, kind) {}
                property var visibleArtwork: ({})
                function set_visible_artwork_games(view, ids, kind) {
                    visibleArtwork[view] = JSON.parse(ids)
                }
                Component.onCompleted: {
                    for (let i = 0; i < 36; ++i)
                        append({ gameId: "game-" + i, gameTitle: "Game " + i,
                            gameCanonicalTitle: "Game " + i, gamePlatform: "Arcade",
                            gameLocal: true, gameDownloadable: false,
                            gameDatabaseId: i + 1, gameMediaId: i + 1,
                            gameStatus: "Installed" })
                }
            }
        }
    }
    SignalSpy { id: selectionReport; signalName: "currentGameChanged" }
    function test_selection_is_republished_only_after_filter_finishes() {
        const browser = createTemporaryObject(browserComponent, this)
        browser.currentIndex = 17
        tryVerify(() => browser.currentItem && browser.currentItem.index === 17)
        wait(350)
        selectionReport.target = browser; selectionReport.clear()
        browser.library.filtering = true
        browser.reportSelection()
        compare(selectionReport.count, 0)
        browser.library.filtering = false
        tryCompare(selectionReport, "count", 1)
        compare(browser.currentItem.gameId, "game-17")
        selectionReport.target = null
    }
    function test_all_views_preserve_identity() {
        const browser = createTemporaryObject(browserComponent, this)
        verify(browser)
        tryCompare(browser, "count", 36)
        browser.currentIndex = 17
        for (const style of ["wheel", "shelf", "wall", "album", "wheel"]) {
            browser.viewStyle = style
            browser.positionViewAtIndex(17, ListView.Center)
            tryVerify(function() { return browser.currentItem !== null }, 1500,
                      style + " has no current item at " + browser.currentIndex)
            tryCompare(browser, "currentIndex", 17)
            tryVerify(function() { return browser.currentItem.gameId === "game-17" },
                      1500, style + " selected " + browser.currentItem.gameId)
        }
    }
    function test_wall_rows_and_final_item() {
        const browser = createTemporaryObject(browserComponent, this, { viewStyle: "wall" })
        tryCompare(browser, "count", 36)
        verify(browser.columns >= 3)
        browser.currentIndex = browser.columns
        browser.positionViewAtIndex(browser.currentIndex, ListView.Contain)
        tryVerify(function() { return browser.currentItem && browser.currentItem.gameId === "game-" + browser.columns })
        browser.currentIndex = 35
        browser.positionViewAtEnd()
        tryVerify(function() { return browser.currentItem && browser.currentItem.gameId === "game-35" })
    }
    function test_switching_to_wall_keeps_selected_cover_fully_visible() {
        const browser = createTemporaryObject(browserComponent, this, {width: 1800, height: 658})
        tryCompare(browser, "count", 36)
        browser.currentIndex = 7
        browser.viewStyle = "wall"
        tryVerify(function() { return browser.currentItem && browser.currentItem.gameId === "game-7" })
        browser.height = 450
        tryVerify(function() {
            const card = browser.currentItem
            const position = card.mapToItem(browser, 0, 0)
            return position.y >= -1 && position.y + card.height <= browser.height + 1
        }, 1000, "The selected wall cover must not be clipped by the viewport")
    }
    function test_all_views_report_visible_media_and_clear_old_view() {
        const browser = createTemporaryObject(browserComponent, this)
        tryCompare(browser, "count", 36)
        browser.currentIndex = 17
        for (const style of ["wheel", "shelf", "wall", "album"]) {
            browser.viewStyle = style
            browser.positionViewAtIndex(17, ListView.Center)
            const key = style === "shelf" ? "couch-shelf"
                        : style === "wall" ? "couch-wall" : "couch-path"
            tryVerify(() => (browser.library.visibleArtwork[key] || []).includes("game-17"),
                      1500, style + " should prioritize its displayed selection")
            for (const other of ["couch-shelf", "couch-wall", "couch-path"]) {
                if (other !== key)
                    compare((browser.library.visibleArtwork[other] || []).length, 0,
                            "Destroyed " + other + " must release its priority")
            }
        }
    }
    SignalSpy { id: activation; signalName: "cardActivated" }
    function test_carousel_focus_depth_and_tilt_data() {
        return ["wheel", "album"].map(style => ({tag: style, style: style}))
    }
    function test_carousel_focus_depth_and_tilt(data) {
        const browser = createTemporaryObject(browserComponent, this, {viewStyle: data.style})
        tryCompare(browser, "count", 36)
        browser.currentIndex = 17
        tryVerify(() => browser.currentItem && browser.currentItem.index === 17)
        wait(450)
        const carousel = findChild(browser, "couchGameCarousel")
        compare(carousel.pathItemCount, 11)
        const focused = browser.currentItem
        const neighbor = focused.parent.children.find(item => item.index === 18)
        verify(neighbor)
        verify(focused.scale > neighbor.scale * 1.3, "The focused entry must visibly magnify")
        verify(focused.z > neighbor.z, "The focused entry must draw in front")
        if (data.style === "wheel") {
            verify(Math.abs(neighbor.rotation) > 8, "Neighboring logos must rotate along the arc")
            compare(findChild(focused, "couchGameCardFrame").color.a, 0)
        } else verify(focused.coverFlow)
    }
    function test_overlapping_neighbor_can_be_clicked_data() {
        return ["wheel", "album"].map(style => ({tag: style, style: style}))
    }
    function test_overlapping_neighbor_can_be_clicked(data) {
        const browser = createTemporaryObject(browserComponent, this, {viewStyle: data.style})
        tryCompare(browser, "count", 36)
        browser.currentIndex = 17
        tryVerify(() => browser.currentItem && browser.currentItem.index === 17)
        wait(450)
        const neighbor = browser.currentItem.parent.children.find(item => item.index === 18)
        verify(neighbor)
        activation.target = browser; activation.clear()
        mouseClick(neighbor, neighbor.width / 2, neighbor.height / 2)
        compare(activation.count, 1)
        compare(activation.signalArguments[0][0], 18)
        activation.target = null
        mouseMove(this, 1200, 690)
    }
    function test_expanding_layout_under_parked_pointer_keeps_game() {
        const browser = createTemporaryObject(browserComponent, this, {width: 700})
        mouseMove(browser, 300, 200)
        mouseMove(browser, 305, 205)
        wait(250)
        browser.currentIndex = 17
        tryVerify(() => browser.currentItem && browser.currentItem.index === 17)
        mouseMove(this, 1000, 260)
        wait(300)
        browser.width = 1120
        browser.viewStyle = "wall"
        wait(500)
        compare(browser.currentIndex, 17)
        mouseMove(this, 1200, 690)
    }
    function test_restored_path_selection_cancels_previous_motion_data() {
        return ["wheel", "album"].map(style => ({tag: style, style: style}))
    }
    function test_restored_path_selection_cancels_previous_motion(data) {
        const browser = createTemporaryObject(browserComponent, this, {viewStyle: data.style})
        tryCompare(browser, "count", 36)
        browser.currentIndex = 17
        wait(70)
        browser.currentIndex = 4
        browser.positionViewAtIndex(4, ListView.Center)
        tryVerify(() => browser.currentItem && browser.currentItem.index === 4)
        wait(450)
        compare(browser.currentIndex, 4)
        compare(browser.currentItem.index, 4)
        const center = browser.currentItem.mapToItem(browser,
            browser.currentItem.width / 2, browser.currentItem.height / 2)
        const target = data.style === "wheel" ? browser.height * 0.5 : browser.width * 0.5
        verify(Math.abs((data.style === "wheel" ? center.y : center.x) - target) < 1)
    }
    function test_controller_cancels_hover_dwell_at_navigation_boundary() {
        const browser = createTemporaryObject(browserComponent, this, {viewStyle: "wall"})
        tryCompare(browser, "count", 36)
        browser.currentIndex = 1
        tryVerify(() => browser.currentItem && browser.currentItem.index === 1)
        const card = browser.currentItem
        browser.currentIndex = 0
        mouseMove(card, card.width / 2, card.height / 2)
        mouseMove(card, card.width / 2 + 5, card.height / 2 + 5)
        wait(50)
        browser.cancelPointerSelection()
        wait(250)
        compare(browser.currentIndex, 0)
        mouseMove(this, 1200, 690)
    }
    function test_hover_selects_without_activating_or_chasing_controller_data() {
        return ["wall", "wheel", "album", "shelf"].map(style => ({tag: style, style: style}))
    }
    function test_hover_selects_without_activating_or_chasing_controller(data) {
        const browser = createTemporaryObject(browserComponent, this, { viewStyle: data.style })
        tryCompare(browser, "count", 36)
        browser.currentIndex = 1
        tryVerify(() => browser.currentItem && browser.currentItem.index === 1)
        const card = browser.currentItem
        browser.currentIndex = 0
        wait(300)
        activation.target = browser; activation.clear()
        mouseMove(card, card.width / 2, card.height / 2)
        mouseMove(card, card.width / 2 + 5, card.height / 2 + 5)
        tryCompare(browser, "currentIndex", 1)
        compare(activation.count, 0)
        browser.currentIndex = 2
        wait(450)
        compare(browser.currentIndex, 2)
        browser.hoverSelectionEnabled = false
        mouseMove(card, card.width / 2 + 10, card.height / 2 + 10)
        wait(250)
        compare(browser.currentIndex, 2, "Overlays must disable background hover selection")
        activation.target = null
        mouseMove(this, 1200, 690)
    }
    function test_wall_wheel_keeps_gliding_and_reserves_slim_scrollbar() {
        const browser = createTemporaryObject(browserComponent, this, { viewStyle: "wall" })
        tryCompare(browser, "count", 36)
        const grid = findChild(browser, "couchWallGrid")
        verify(grid)
        verify(grid.defaultWheelMomentum)
        const momentum = findChild(grid, "momentumWheelHandler")
        verify(momentum && momentum.enabled)
        verify(grid.verticalScrollBarGutter <= 14)
        verify(grid.cellWidth * grid.columnCount <= grid.width - grid.verticalScrollBarGutter + 0.01)
        // Wheel input is delivered to a displayed view. Wait for its initial
        // layout/selection polish before measuring a user's scrolling gesture.
        verify(waitForRendering(grid))
        mouseWheel(grid, grid.width / 2, grid.height / 2, 0, -120)
        const immediate = grid.contentY
        verify(immediate > 0, "Wheel input should move immediately")
        verify(momentum.momentumRunning, "Wheel must start momentum; position=" + immediate)
        wait(120)
        verify(grid.contentY > immediate + 10, "Cover wall should keep gliding after the wheel stops; immediate=" + immediate + ", now=" + grid.contentY + ", running=" + momentum.momentumRunning)
    }
    function test_wall_star_toggles_only_favorite() {
        const browser = createTemporaryObject(browserComponent, this, { viewStyle: "wall" })
        tryCompare(browser, "count", 36)
        browser.currentIndex = 1
        tryVerify(function() { return browser.currentItem !== null })
        activation.target = browser
        activation.clear()
        const star = findChild(browser.currentItem, "coverFavoriteButton")
        verify(star)
        verify(star.visible)
        compare(star.favorite, false)
        mouseClick(star)
        tryCompare(star, "favorite", true)
        compare(browser.library.is_favorite("game-1"), true)
        compare(activation.count, 0, "Starring a cover must not open the game")
        mouseClick(star)
        tryCompare(star, "favorite", false)
        compare(activation.count, 0)
        activation.target = null
    }
    function test_small_model_and_empty_library() {
        const browser = createTemporaryObject(browserComponent, this)
        tryCompare(browser, "count", 36)
        browser.library.clear()
        tryCompare(browser, "count", 0)
        for (const style of ["wall", "album", "shelf", "wheel"]) {
            browser.viewStyle = style
            wait(30)
            compare(browser.count, 0)
        }
        browser.library.append({ gameId: "only", gameTitle: "Only game",
            gameCanonicalTitle: "Only game", gamePlatform: "NES", gameLocal: true,
            gameDownloadable: false, gameDatabaseId: 1, gameMediaId: 1, gameStatus: "Installed" })
        for (const style of ["wheel", "album", "wall", "shelf"]) {
            browser.viewStyle = style
            tryCompare(browser, "count", 1)
            tryVerify(function() { return browser.currentItem && browser.currentItem.gameId === "only" })
        }
    }
}
