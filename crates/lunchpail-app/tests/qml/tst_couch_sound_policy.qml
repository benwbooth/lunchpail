import QtQuick
import QtTest
import "../../qml" as Lunchpail

TestCase {
    id: test
    name: "CouchSoundPolicy"
    Component { id: component; Lunchpail.CouchSoundPolicy {} }
    function policy() { const item = createTemporaryObject(component, test); verify(item); return item }
    function test_muting_and_inactivity_gate_all_sounds() {
        const item = policy()
        verify(!item.accept("move", 1000)); item.active = true; item.muted = true
        verify(!item.accept("confirm", 2000)); item.muted = false; item.volume = 0
        verify(!item.accept("launch", 3000))
        item.volume = 0.22; verify(item.accept("enter", 4000))
        verify(!item.accept("unknown", 5000))
    }
    function test_scroll_rate_is_bounded_but_confirm_is_immediate() {
        const item = policy(); item.active = true
        verify(item.accept("move", 1000)); verify(!item.accept("move", 1050))
        verify(item.accept("confirm", 1060)); verify(!item.accept("confirm", 1070))
        verify(item.accept("move", 1100))
    }
    function test_launch_is_not_cut_off_by_controller_confirm() {
        const item = policy(); item.active = true
        verify(item.accept("launch", 1000)); verify(!item.accept("confirm", 1001))
        verify(!item.accept("move", 1100)); verify(item.accept("back", 1101))
        verify(item.accept("switch", 1500))
    }
}
