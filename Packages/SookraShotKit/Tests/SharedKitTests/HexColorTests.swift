import Testing
@testable import SharedKit

@Suite struct HexColorTests {
    @Test func formatsRGB() {
        #expect(HexColor.string(red: 1, green: 0, blue: 0) == "#FF0000")
        #expect(HexColor.string(red: 0, green: 0.5, blue: 1) == "#0080FF")
        #expect(HexColor.string(red: 1, green: 1, blue: 1) == "#FFFFFF")
    }

    @Test func clampsOutOfRange() {
        #expect(HexColor.string(red: -0.5, green: 2, blue: 0) == "#00FF00")
    }
}
