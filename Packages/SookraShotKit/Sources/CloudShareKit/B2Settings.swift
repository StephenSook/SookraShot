import Foundation

public enum B2LinkMode: String, Sendable, CaseIterable {
    case presigned
    case publicURL
}

/// Full config for one upload: secret credentials from the Keychain, plus
/// non-secret bucket/region/link settings from UserDefaults.
public struct B2Config: Sendable {
    public let keyID: String
    public let appKey: String
    public let bucket: String
    public let region: String
    public let linkMode: B2LinkMode
    public let presignedHours: Int
    public let keyPrefix: String
}

/// Reads the non-secret half of the B2 config from UserDefaults and assembles a
/// complete `B2Config` when everything is present.
public enum B2Settings {
    public enum Key {
        public static let bucket = "b2Bucket"
        public static let region = "b2Region"
        public static let linkMode = "b2LinkMode"
        public static let presignedHours = "b2PresignedHours"
        public static let keyPrefix = "b2KeyPrefix"
    }

    private static var defaults: UserDefaults { .standard }

    public static var bucket: String { defaults.string(forKey: Key.bucket) ?? "" }
    public static var region: String { defaults.string(forKey: Key.region) ?? "" }

    public static var linkMode: B2LinkMode {
        defaults.string(forKey: Key.linkMode).flatMap(B2LinkMode.init(rawValue:)) ?? .presigned
    }

    public static var presignedHours: Int {
        let value = defaults.integer(forKey: Key.presignedHours)
        return value > 0 ? value : 168
    }

    public static var keyPrefix: String {
        let value = defaults.string(forKey: Key.keyPrefix) ?? "sookrashot/"
        return value.isEmpty ? "" : (value.hasSuffix("/") ? value : value + "/")
    }

    public static var isConfigured: Bool { current != nil }

    public static var current: B2Config? {
        guard let credentials = B2CredentialStore.credentials else { return nil }
        let bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bucket.isEmpty, !region.isEmpty else { return nil }
        return B2Config(
            keyID: credentials.keyID,
            appKey: credentials.appKey,
            bucket: bucket,
            region: region,
            linkMode: linkMode,
            presignedHours: presignedHours,
            keyPrefix: keyPrefix
        )
    }
}
