import AppKit
import KeyboardShortcuts

/// Global capture hotkeys. KeyboardShortcuts wraps Carbon RegisterEventHotKey,
/// so no Input Monitoring / Accessibility permission is required.
///
/// Defaults mirror the system screenshot keys — the user disables the system
/// ones once in System Settings > Keyboard > Keyboard Shortcuts > Screenshots.
extension KeyboardShortcuts.Name {
    public static let captureFullscreen = Self("captureFullscreen", default: .init(.three, modifiers: [.command, .shift]))
    public static let captureArea = Self("captureArea", default: .init(.four, modifiers: [.command, .shift]))
    public static let allInOne = Self("allInOne", default: .init(.five, modifiers: [.command, .shift]))
    public static let captureText = Self("captureText", default: .init(.two, modifiers: [.command, .shift]))
    public static let recordScreen = Self("recordScreen", default: .init(.six, modifiers: [.command, .shift]))
    public static let scrollingCapture = Self("scrollingCapture", default: .init(.seven, modifiers: [.command, .shift]))
    public static let askClaude = Self("askClaude", default: .init(.eight, modifiers: [.command, .shift]))
}

public enum HotkeyAction: CaseIterable, Sendable {
    case captureFullscreen
    case captureArea
    case allInOne
    case captureText
    case recordScreen
    case scrollingCapture
    case askClaude

    var name: KeyboardShortcuts.Name {
        switch self {
        case .captureFullscreen: .captureFullscreen
        case .captureArea: .captureArea
        case .allInOne: .allInOne
        case .captureText: .captureText
        case .recordScreen: .recordScreen
        case .scrollingCapture: .scrollingCapture
        case .askClaude: .askClaude
        }
    }
}

@MainActor
public final class HotkeyCenter {
    public init() {}

    public func onActivate(_ handler: @escaping @MainActor (HotkeyAction) -> Void) {
        for action in HotkeyAction.allCases {
            KeyboardShortcuts.onKeyUp(for: action.name) {
                handler(action)
            }
        }
    }
}
