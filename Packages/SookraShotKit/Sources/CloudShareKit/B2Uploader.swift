import Foundation

public struct B2Error: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// Uploads PNG data to a Backblaze B2 bucket via the S3-compatible API and
/// returns a shareable link (presigned or public per the config).
public struct B2Uploader: Sendable {
    public init() {}

    public func upload(pngData: Data, config: B2Config, now: Date = Date()) async throws -> URL {
        let key = objectKey(prefix: config.keyPrefix, now: now)
        let host = "\(config.bucket).s3.\(config.region).backblazeb2.com"
        let encodedPath = "/" + key
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { AWSV4Signer.uriEncode(String($0), encodeSlash: true) }
            .joined(separator: "/")

        let payloadHash = AWSV4Signer.sha256Hex(pngData)
        let signer = AWSV4Signer(accessKeyID: config.keyID, secretKey: config.appKey, region: config.region)
        let headers = signer.signedPutHeaders(host: host, encodedPath: encodedPath, payloadSHA256Hex: payloadHash, now: now)

        guard let url = URL(string: "https://\(host)\(encodedPath)") else {
            throw B2Error(message: "Invalid bucket or region.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (responseData, response) = try await URLSession.shared.upload(for: request, from: pngData)
        guard let http = response as? HTTPURLResponse else {
            throw B2Error(message: "No response from Backblaze.")
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = Self.parseError(responseData) ?? "HTTP \(http.statusCode)"
            throw B2Error(message: "Upload failed: \(detail)")
        }

        switch config.linkMode {
        case .publicURL:
            return url
        case .presigned:
            guard let link = signer.presignedGetURL(
                host: host, encodedPath: encodedPath,
                expiresSeconds: config.presignedHours * 3600, now: now
            ) else {
                throw B2Error(message: "Could not sign the share link.")
            }
            return link
        }
    }

    private func objectKey(prefix: String, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return "\(prefix)\(stamp)-\(suffix).png"
    }

    /// Backblaze returns an XML `<Error><Message>…</Message></Error>` body.
    private static func parseError(_ data: Data) -> String? {
        guard let body = String(data: data, encoding: .utf8),
              let open = body.range(of: "<Message>"),
              let close = body.range(of: "</Message>")
        else { return nil }
        return String(body[open.upperBound..<close.lowerBound])
    }
}
