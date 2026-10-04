import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: testCase
    name: "ControllerMappingView"
    when: windowShown

    Component {
        id: hostComponent

        ApplicationWindow {
            width: 1000
            height: 800
            visible: true

            QtObject {
                id: settingsState
                property var diagramRequests: []
                property int controller_revision: 0
                property var calibration: ({layout: "source-pad", bindings: {
                    a: {code: 10, kind: "button", direction: 0, logical: "South"},
                    b: {code: 11, kind: "button", direction: 0, logical: "East"}
                }})
                function controller_calibration_json(device) { return JSON.stringify(calibration) }
                function controller_key_for_input(key) { return key === "raw-pad" ? "saved-pad" : "other-pad" }
                function controller_diagram(layoutId, highlight) {
                    diagramRequests.push(layoutId)
                    return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="900" height="500"><rect width="900" height="500" fill="#202a39"/></svg>')
                }
            }

            QtObject {
                id: pad
                property int input_revision: 0
                property string last_device_key: "raw-pad"
                property string last_binding: "{}"
                function press(binding, device) {
                    last_device_key = device || "raw-pad"
                    last_binding = JSON.stringify(binding)
                    input_revision++
                }
            }

            Lunchpail.ControllerMappingView {
                id: mapping
                anchors.fill: parent
                settingsModel: settingsState
                sourceLayout: ({
                    id: "source-pad", name: "Source pad",
                    controls: [
                        {id: "a", label: "A", x: 10, y: 20},
                        {id: "b", label: "B", x: 30, y: 20}
                    ]
                })
                destinationLayout: ({
                    id: "target-pad", name: "Target pad",
                    controls: [
                        {id: "x", label: "X", x: 10, y: 20},
                        {id: "y", label: "Y", x: 30, y: 20}
                    ]
                })
                rows: [
                    {physical_id: "a", physical: "A", target_id: "x", target: "X",
                     output: "X..West", reason: "Same semantic control"},
                    {physical_id: "b", physical: "B", target_id: "y", target: "Y",
                     output: "A..South", reason: "Same semantic control"}
                ]
            }

            property alias mapping: mapping
            property alias diagramRequests: settingsState.diagramRequests
            property alias settings: settingsState
            property alias pad: pad
        }
    }

    function liveHost() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        host.mapping.gamepad = host.pad
        host.mapping.sourceDeviceId = "saved-pad"
        return host
    }

    function test_live_press_highlights_wire_and_both_controls_without_changing_pin() {
        const host = liveHost()
        host.mapping.chooseControl(1, "y")
        host.mapping.hoveredIndex = 1
        const before = JSON.stringify(host.mapping.rows)
        const bindings = JSON.stringify(host.mapping.sourceBindings)
        host.pad.press({code: 10, kind: "button", direction: 0, logical: "Different label"})
        compare(host.mapping.highlightedSourceId(), "a")
        compare(host.mapping.highlightedDestId(), "x")
        verify(host.mapping.wireHighlighted(false, 0))
        verify(!host.mapping.wireHighlighted(false, 1))
        verify(findChild(host.mapping, "controllerControl0_a").highlighted)
        verify(findChild(host.mapping, "controllerControl1_x").highlighted)
        verify(!findChild(host.mapping, "controllerControl1_y").highlighted)
        compare(host.mapping.selectedIndex, 1)
        compare(JSON.stringify(host.mapping.rows), before)
        compare(JSON.stringify(host.mapping.sourceBindings), bindings)
        verify(findChild(host.mapping, "controllerLiveMappingFeedback").text.indexOf("A → X") >= 0)
        tryCompare(host.mapping, "liveSourceIds", [], 2000)
        compare(host.mapping.highlightedSourceId(), "b")
        compare(host.mapping.selectedIndex, 1)
    }

    function test_live_input_is_scoped_to_device_and_not_logical_name() {
        const host = liveHost()
        host.pad.press({code: 10, kind: "button", direction: 0, logical: "South"}, "other-raw-pad")
        compare(host.mapping.liveSourceIds.length, 0)
        host.pad.press({code: 99, kind: "button", direction: 0, logical: "South"})
        compare(host.mapping.liveSourceIds.length, 0)
        host.pad.last_binding = "not JSON"
        host.pad.input_revision++
        compare(host.mapping.liveSourceIds.length, 0)
        host.mapping.sourceDeviceId = ""
        host.pad.press({code: 10, kind: "button", direction: 0})
        compare(host.mapping.liveSourceIds.length, 0)
    }

    function test_live_press_highlights_all_shared_and_twin_routes() {
        const host = liveHost()
        host.mapping.rows = host.mapping.rows.concat([
            {physical_id: "a", physical: "A", target_id: "y", target: "Y", reason: "Shared"}
        ])
        host.mapping.twinRoutes = [{physical_id: "a", target_id: "y", output: "Turbo Y"}]
        host.pad.press({code: 10, kind: "button", direction: 0})
        compare(host.mapping.liveRows.length, 3)
        verify(host.mapping.wireHighlighted(false, 0))
        verify(!host.mapping.wireHighlighted(false, 1))
        verify(host.mapping.wireHighlighted(false, 2))
        verify(host.mapping.wireHighlighted(true, 0))
        verify(host.mapping.controlHighlighted(1, "x"))
        verify(host.mapping.controlHighlighted(1, "y"))
    }

    function test_live_twin_only_and_unassigned_controls() {
        const host = liveHost()
        host.mapping.rows = [host.mapping.rows[0]]
        host.mapping.twinRoutes = [{physical_id: "b", target_id: "x", output: "Turbo X"}]
        host.pad.press({code: 11, kind: "button", direction: 0})
        compare(host.mapping.highlightedSourceId(), "b")
        compare(host.mapping.highlightedDestId(), "x")
        verify(host.mapping.wireHighlighted(true, 0))
        host.mapping.twinRoutes = []
        host.pad.press({code: 11, kind: "button", direction: 0})
        compare(host.mapping.highlightedSourceId(), "b")
        compare(host.mapping.highlightedDestId(), "")
        verify(findChild(host.mapping, "controllerLiveMappingFeedback").text.indexOf("no assignment") >= 0)
    }

    function test_live_physical_axis_identity_and_direction() {
        const host = liveHost()
        host.mapping.sourceBindings = {
            a: {code: 10, kind: "button", direction: 0, native: {code: 196624, direction: -1}},
            b: {code: 11, kind: "button", direction: 0, native: {code: 196624, direction: 1}}
        }
        host.pad.press({code: 10, kind: "button", direction: 0, native: {code: 196624, direction: 1}})
        compare(host.mapping.highlightedSourceId(), "b")
        host.pad.press({code: 10, kind: "button", direction: 0, native: {code: 196625, direction: 1}})
        compare(host.mapping.liveSourceIds.length, 0)
        host.mapping.sourceLayout = {id: "source-pad", name: "Analog pad", controls: [
            {id: "a", label: "Stick X", analog: true, x: 10, y: 20}
        ]}
        host.pad.press({code: 10, kind: "axis", direction: 1, native: {code: 196624, direction: 1}})
        compare(host.mapping.highlightedSourceId(), "a")
        host.pad.press({code: 10, kind: "axis", direction: -1, native: {code: 196624, direction: -1}})
        compare(host.mapping.highlightedSourceId(), "a")
    }

    function test_live_repeated_hardware_positions_share_highlight() {
        const host = liveHost()
        host.mapping.sourceLayout = {id: "source-pad", name: "Repeated face", controls: [
            {id: "a", label: "A", x: 10, y: 20},
            {id: "a-repeat", label: "A repeat", repeat_of: "a", x: 30, y: 20}
        ]}
        host.pad.press({code: 10, kind: "button", direction: 0})
        verify(host.mapping.controlHighlighted(0, "a"))
        verify(host.mapping.controlHighlighted(0, "a-repeat"))
        compare(host.mapping.liveRows.length, 1)
    }

    function test_live_input_clears_when_hidden_disabled_or_reconfigured() {
        const host = liveHost()
        const input = {code: 10, kind: "button", direction: 0}
        host.pad.press(input)
        compare(host.mapping.liveSourceIds.length, 1)
        host.mapping.inputFeedbackEnabled = false
        compare(host.mapping.liveSourceIds.length, 0)
        host.pad.press(input)
        compare(host.mapping.liveSourceIds.length, 0)
        host.mapping.inputFeedbackEnabled = true
        host.pad.press(input)
        host.mapping.visible = false
        compare(host.mapping.liveSourceIds.length, 0)
        host.pad.press(input)
        compare(host.mapping.liveSourceIds.length, 0)
        host.mapping.visible = true
        host.pad.press(input)
        host.mapping.sourceDeviceId = "other-pad"
        compare(host.mapping.liveSourceIds.length, 0)
        host.mapping.sourceDeviceId = "saved-pad"
        host.pad.press(input)
        host.settings.calibration = {layout: "unrelated-layout", bindings: {a: input}}
        compare(host.mapping.liveSourceIds.length, 0)
        host.pad.press(input)
        compare(host.mapping.liveSourceIds.length, 0)
    }

    function test_turbo_routes_have_explicit_labels_and_tooltips() {
        const host = createTemporaryObject(hostComponent, testCase)
        host.mapping.twinRoutes = [{physical_id:"b", target_id:"x", target_label:"Turbo A",
            output:"RetroPad X", reason:"Hold for rapid fire"}]
        compare(host.mapping.secondaryRows[0].target,"Turbo A")
        const tip = host.mapping.controlTooltip(0,host.mapping.sourceLayout.controls[1]).plain
        verify(tip.indexOf("Turbo A") >= 0)
        verify(tip.indexOf("Hold for rapid fire") >= 0)
        verify(tip.indexOf("shares one input") < 0)
    }

    function test_diagram_selects_connections_without_any_list() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        compare(host.mapping.rows.length, 2)
        compare(host.mapping.hoveredIndex, -1)
        // Nothing is pinned on load: no row looks pre-selected.
        compare(host.mapping.selectedIndex, -1)
        verify(!host.mapping.selected)
        compare(host.mapping.highlightedSourceId(), "")
        compare(host.mapping.highlightedDestId(), "")

        // Clicking a diagram control pins its connection.
        host.mapping.chooseControl(1, "y")
        compare(host.mapping.selectedIndex, 1)
        compare(host.mapping.selected.target_id, "y")
        compare(host.mapping.selected.output, "A..South")

        // Hover state isolates a wire while the stored pin stays put.
        host.mapping.hoveredIndex = 0
        compare(host.mapping.hoveredIndex, 0)
        compare(host.mapping.selected.target_id, "y")
        host.mapping.hoveredIndex = -1
    }

    function test_artwork_highlight_follows_the_pointer_not_the_pin() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        // Pin the second row, then hover the first: artwork follows hover.
        host.mapping.chooseControl(1, "y")
        compare(host.mapping.selectedIndex, 1)
        host.mapping.hoveredIndex = 0
        compare(host.mapping.highlightedSourceId(), "a")
        compare(host.mapping.highlightedDestId(), "x")
        // Clearing the hover falls back to the pin, never to a third row.
        host.mapping.hoveredIndex = -1
        compare(host.mapping.highlightedSourceId(), "b")
        compare(host.mapping.highlightedDestId(), "y")
    }

    function test_hover_and_selection_do_not_reload_the_artwork() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        tryVerify(() => findChild(host.mapping, "controllerArtwork0") !== null)
        const artwork = findChild(host.mapping, "controllerArtwork0")
        const button = findChild(host.mapping, "controllerControl0_a")
        verify(artwork && button)
        tryCompare(artwork, "status", Image.Ready)
        const calls = host.diagramRequests.length
        const source = artwork.source.toString()
        for (let index = 0; index < 12; ++index) {
            host.mapping.hoveredIndex = index % 2
            compare(button.highlighted, index % 2 === 0)
            host.mapping.chooseControl(1, index % 2 ? "x" : "y")
            waitForRendering(host.mapping)
            compare(artwork.status, Image.Ready)
            compare(artwork.source.toString(), source)
        }
        compare(host.diagramRequests.length, calls)
    }

    function test_unmapped_control_clears_the_pin() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        host.mapping.chooseControl(0, "missing")
        compare(host.mapping.selectedIndex, -1)
        verify(!host.mapping.selected)
    }

    function test_tooltip_names_both_ends_with_emulator_output() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        const tip = host.mapping.controlTooltip(0, {id: "a", label: "A"})
        verify(tip.rich.indexOf("drives") >= 0)
        verify(tip.rich.indexOf("#ffb454") >= 0)
        verify(tip.rich.indexOf("#62dac8") >= 0)
        verify(tip.rich.indexOf("X..West") >= 0)
        verify(tip.plain.indexOf("<") < 0)
        verify(tip.plain.indexOf("X..West") >= 0)
        const flipped = host.mapping.controlTooltip(1, {id: "y", label: "Y"})
        verify(flipped.rich.indexOf("driven by") >= 0)
    }

    function test_twin_inputs_render_as_shared_wires() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        compare(host.mapping.secondaryRows.length, 0)
        host.mapping.twinRoutes = [{target_id: "x", physical_id: "b2", output: "X..West"}]
        compare(host.mapping.secondaryRows.length, 1)
        compare(host.mapping.secondaryRows[0].physical, "b2")
        compare(host.mapping.secondaryRows[0].target, "X")
        const tip = host.mapping.controlTooltip(0, {id: "b2", label: "B2"})
        verify(tip.rich.indexOf("also drives") >= 0)
        verify(tip.rich.indexOf("shares one input") >= 0)
        verify(tip.rich.indexOf("X..West") >= 0)
    }

    function test_lane_helper_spreads_wires_across_the_channel() {
        const host = createTemporaryObject(hostComponent, testCase)
        verify(host)
        const first = host.mapping.laneXFor(0, 3, 100, 400)
        const middle = host.mapping.laneXFor(1, 3, 100, 400)
        const last = host.mapping.laneXFor(2, 3, 100, 400)
        verify(first < middle && middle < last)
        verify(first >= 100 && last <= 400)
        compare(host.mapping.laneXFor(0, 1, 100, 400), 250)
    }
}
