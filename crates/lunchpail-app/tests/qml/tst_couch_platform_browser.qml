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
                property int media_revision: 0
                function platform_name_at(index) { return "Platform " + index }
                function platform_game_count_at(index) { return index * 100 + 1 }
                function platform_media_url(platform, type) { return "" }
            }
        }
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
}
