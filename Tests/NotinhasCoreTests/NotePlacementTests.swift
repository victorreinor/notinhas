import CoreGraphics
import Testing
@testable import NotinhasCore

private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
private let monitor = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
private let onMonitor = CGRect(x: 2200, y: 600, width: 260, height: 240)
private let onLaptop = CGRect(x: 100, y: 100, width: 260, height: 240)

@Suite struct Placement {
    @Test func leavesNotesThatAreHome() {
        let targets = NotePlacement.targets(
            homes: [onMonitor, onLaptop], windows: [onMonitor, onLaptop], screens: [laptop, monitor], fallback: laptop)
        #expect(targets == [nil, nil])
    }

    @Test func cascadesNotesWhoseMonitorIsGoneOntoTheFallbackScreen() {
        let other = CGRect(x: 2600, y: 500, width: 300, height: 200)
        let targets = NotePlacement.targets(
            homes: [onMonitor, onLaptop, other], windows: [onMonitor, onLaptop, other], screens: [laptop], fallback: laptop)
        #expect(targets == [
            CGRect(x: 1440 - 260 - 48, y: 875 - 240 - 48, width: 260, height: 240),
            nil,
            CGRect(x: 1440 - 300 - 48 - 28, y: 875 - 200 - 48 - 28, width: 300, height: 200),
        ])
    }

    @Test func leavesNotesAlreadyWaitingInPlace() {
        let waiting = CGRect(x: 1440 - 260 - 48, y: 875 - 240 - 48, width: 260, height: 240)
        let targets = NotePlacement.targets(homes: [onMonitor], windows: [waiting], screens: [laptop], fallback: laptop)
        #expect(targets == [nil])
    }

    @Test func sendsNotesHomeWhenTheirMonitorReturns() {
        let waiting = CGRect(x: 1440 - 260 - 48, y: 875 - 240 - 48, width: 260, height: 240)
        let targets = NotePlacement.targets(homes: [onMonitor], windows: [waiting], screens: [laptop, monitor], fallback: laptop)
        #expect(targets == [onMonitor])
    }
}
