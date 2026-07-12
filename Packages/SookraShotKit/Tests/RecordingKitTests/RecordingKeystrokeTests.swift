import AppKit
import Testing
@testable import RecordingKit

@Suite struct RecordingKeystrokeTests {
    @Test func mapsModifiersLettersAndSpecials() {
        #expect(RecordingKeystroke.displayString(keyCode: 8, modifiers: [.command], characters: "c") == "⌘C")
        #expect(RecordingKeystroke.displayString(keyCode: 0, modifiers: [], characters: "a") == "A")
        #expect(RecordingKeystroke.displayString(keyCode: 36, modifiers: [], characters: "\r") == "⏎")
        #expect(RecordingKeystroke.displayString(keyCode: 8, modifiers: [.command, .shift], characters: "c") == "⇧⌘C")
        #expect(RecordingKeystroke.displayString(keyCode: 123, modifiers: [], characters: nil) == "←")
    }

    @Test func nilForEmpty() {
        #expect(RecordingKeystroke.displayString(keyCode: 200, modifiers: [], characters: "") == nil)
    }
}
