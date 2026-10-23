import Testing
@testable import PulseCore

@Test("PulseCore exposes a version")
func coreHasVersion() {
    #expect(PulseCore.version == "0.1.0")
}
