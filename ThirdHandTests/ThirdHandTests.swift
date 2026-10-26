import Testing
@testable import ThirdHand
import ThirdHandCore

@Suite("App scaffold")
struct ThirdHandAppTests {
    @Test("Core is linked into the app")
    func coreIsLinked() {
        #expect(ThirdHandCore.version.isEmpty == false)
    }
}
