import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    name: "CouchPlatformBrowser"
    when: windowShown
    visible: true; width: 1280; height: 720
    Component {
        id: browserComponent
        Lunchpail.CouchPlatformBrowser {
            width: 900; height: 530
            library: QtObject {
                property int platform_count: 36
                property int platform_revision: 0
                property var filteredIndices: [7, 22]
                property int filtered_platform_count: filteredIndices.length
                property int media_revision: 0
                property int logoRequests: 0
                property string lastMediaKind: ""
                function request_platform_logos() { logoRequests++ }
                function platform_name_at(index) { return "Platform " + index }
                function platform_game_count_at(index) { return index * 100 + 1 }
                function filtered_platform_name_at(index) { return platform_name_at(filteredIndices[index]) }
                function filtered_platform_game_count_at(index) { return platform_game_count_at(filteredIndices[index]) }
                function platform_media_url(platform, type) { lastMediaKind = type; return "" }
            }
        }
    }
    function test_wheel_requests_real_system_wheels_and_refreshes_after_download() {
        const browser = createTemporaryObject(browserComponent, this)
        tryVerify(() => browser.library.logoRequests > 0)
        tryVerify(() => browser.currentItem !== null)
        compare(browser.library.lastMediaKind, "wheel-logo")
        browser.library.lastMediaKind = ""
        browser.library.media_revision++
        tryCompare(browser.library, "lastMediaKind", "wheel-logo")
        browser.visible = false
        const requests = browser.library.logoRequests
        browser.library.platform_count = 20
        wait(50)
        compare(browser.library.logoRequests, requests)
        browser.visible = true
        tryVerify(() => browser.library.logoRequests > requests)
    }
    function test_all_views_preserve_platform_identity() {
        const browser = createTemporaryObject(browserComponent, this)
        browser.currentIndex = 17
        for (const style of ["wheel", "wall", "album", "shelf", "wheel"]) {
            browser.viewStyle = style
            tryVerify(() => browser.currentItem && browser.currentItem.index === 17, 2000,
                      style + " must preserve platform 17")
            compare(browser.currentItem.platformName, "Platform 17")
        }
    }
    function test_wall_has_rows_and_keeps_last_platform_visible() {
        const browser = createTemporaryObject(browserComponent, this, { viewStyle: "wall" })
        verify(browser.columns >= 2)
        browser.currentIndex = 35
        browser.positionViewAtEnd()
        tryVerify(() => browser.currentItem && browser.currentItem.index === 35)
        browser.height = 320
        tryVerify(() => {
            const item = browser.currentItem
            const point = item.mapToItem(browser, 0, 0)
            return point.y >= -1 && point.y + item.height <= browser.height + 1
        })
    }
    function test_expanding_layout_under_parked_pointer_keeps_platform() {
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
    SignalSpy { id: activation; signalName: "activated" }
    function test_wheel_uses_the_same_dense_magnifying_path_as_games() {
        const browser = createTemporaryObject(browserComponent, this)
        browser.currentIndex = 17
        tryVerify(() => browser.currentItem && browser.currentItem.index === 17)
        wait(450)
        const carousel = findChild(browser, "couchPlatformCarousel")
        compare(carousel.pathItemCount, 11)
        const focused = browser.currentItem
        const neighbor = focused.parent.children.find(item => item.index === 18)
        verify(neighbor)
        verify(focused.scale > neighbor.scale * 1.3)
        verify(focused.z > neighbor.z)
        verify(Math.abs(neighbor.rotation) > 8)
        compare(focused.objectName, "couchWheelLogo")
        compare(focused.opacity, 1)
        verify(!findChild(focused, "couchPlatformCardFrame"))
        activation.target = browser; activation.clear()
        mouseClick(neighbor, neighbor.width / 2, neighbor.height / 2)
        compare(activation.count, 1)
        compare(activation.signalArguments[0][0], 18)
        activation.target = null
        mouseMove(this, 1200, 690)
    }
    function test_hover_selects_without_entering_platform_data() {
        return ["wall", "wheel", "album", "shelf"].map(style => ({tag: style, style: style}))
    }
    function test_hover_selects_without_entering_platform(data) {
        const browser = createTemporaryObject(browserComponent, this, { viewStyle: data.style })
        activation.target = browser; activation.clear()
        browser.currentIndex = 1
        tryVerify(() => browser.currentItem && browser.currentItem.index === 1)
        const card = browser.currentItem
        browser.currentIndex = 0
        wait(300)
        mouseMove(card, card.width / 2, card.height / 2)
        mouseMove(card, card.width / 2 + 4, card.height / 2 + 4)
        tryCompare(browser, "currentIndex", 1)
        compare(activation.count, 0)
        browser.currentIndex = 2
        wait(450)
        compare(browser.currentIndex, 2, "A parked mouse cannot undo controller selection")
        activation.target = null
        mouseMove(this, 1200, 690)
    }
    function test_empty_and_single_platform() {
        const browser = createTemporaryObject(browserComponent, this)
        browser.library.platform_count = 0
        for (const style of ["wall", "album", "wheel", "shelf"]) {
            browser.viewStyle = style
            compare(browser.count, 0)
            wait(20)
        }
        browser.library.platform_count = 1
        browser.currentIndex = 0
        for (const style of ["wall", "album", "wheel", "shelf"]) {
            browser.viewStyle = style
            tryVerify(() => browser.currentItem && browser.currentItem.index === 0)
        }
    }
    function test_filtered_cards_track_identity_even_when_result_count_is_unchanged_data() {
        return ["wall", "wheel", "album", "shelf"].map(style => ({tag: style, style: style}))
    }
    function test_filtered_cards_track_identity_even_when_result_count_is_unchanged(data) {
        const browser = createTemporaryObject(browserComponent, this, {filtered: true, viewStyle: data.style})
        compare(browser.count, 2)
        tryVerify(() => browser.currentItem && browser.currentItem.platformName === "Platform 7")
        if (data.style !== "wheel") compare(browser.currentItem.gameCount, 701)
        browser.library.filteredIndices = [5, 8]
        browser.library.platform_revision++
        compare(browser.count, 2)
        tryVerify(() => browser.currentItem && browser.currentItem.platformName === "Platform 5")
        browser.currentIndex = 1
        tryVerify(() => browser.currentItem && browser.currentItem.platformName === "Platform 8")
        compare(browser.nameAt(browser.currentIndex), "Platform 8")
        browser.library.filteredIndices = []
        browser.library.platform_revision++
        compare(browser.count, 0)
    }
}
