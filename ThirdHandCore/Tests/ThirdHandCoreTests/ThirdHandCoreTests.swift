import Testing
@testable import ThirdHandCore

@Test("ThirdHandCore exposes a version")
func coreHasVersion() {
    #expect(ThirdHandCore.version == "0.1.0")
}
