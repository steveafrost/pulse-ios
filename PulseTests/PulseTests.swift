import Testing
@testable import Pulse
import PulseCore

@Suite("App scaffold")
struct PulseAppTests {
    @Test("Core is linked into the app")
    func coreIsLinked() {
        #expect(PulseCore.version.isEmpty == false)
    }
}
