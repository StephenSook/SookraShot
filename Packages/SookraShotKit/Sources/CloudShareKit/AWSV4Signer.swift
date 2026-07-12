import CryptoKit
import Foundation

/// AWS Signature Version 4 for S3-compatible endpoints (Backblaze B2 speaks
/// this). Supports header-auth for PUT and query-auth for presigned GET URLs.
struct AWSV4Signer: Sendable {
    let accessKeyID: String
    let secretKey: String
    let region: String
    let service = "s3"

    /// Headers to attach to a PUT upload of a payload with the given hash.
    func signedPutHeaders(host: String, encodedPath: String, payloadSHA256Hex: String, now: Date) -> [String: String] {
        let (amzDate, dateStamp) = Self.dates(now)
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(payloadSHA256Hex)\nx-amz-date:\(amzDate)\n"
        let canonicalRequest = [
            "PUT",
            encodedPath,
            "",
            canonicalHeaders,
            signedHeaders,
            payloadSHA256Hex,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let signature = Self.hmacHex(signingKey(dateStamp), stringToSign)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return [
            "x-amz-date": amzDate,
            "x-amz-content-sha256": payloadSHA256Hex,
            "Authorization": authorization,
        ]
    }

    /// A presigned GET URL valid for `expiresSeconds`.
    func presignedGetURL(host: String, encodedPath: String, expiresSeconds: Int, now: Date) -> URL? {
        let (amzDate, dateStamp) = Self.dates(now)
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let credential = Self.uriEncode("\(accessKeyID)/\(scope)", encodeSlash: true)
        let params: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", credential),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(expiresSeconds)),
            ("X-Amz-SignedHeaders", "host"),
        ]
        let canonicalQuery = params.sorted { $0.0 < $1.0 }.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let canonicalRequest = [
            "GET",
            encodedPath,
            canonicalQuery,
            "host:\(host)\n",
            "host",
            "UNSIGNED-PAYLOAD",
        ].joined(separator: "\n")

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let signature = Self.hmacHex(signingKey(dateStamp), stringToSign)
        return URL(string: "https://\(host)\(encodedPath)?\(canonicalQuery)&X-Amz-Signature=\(signature)")
    }

    // MARK: - Signing primitives

    private func signingKey(_ dateStamp: String) -> Data {
        let kDate = Self.hmac(Data("AWS4\(secretKey)".utf8), Data(dateStamp.utf8))
        let kRegion = Self.hmac(kDate, Data(region.utf8))
        let kService = Self.hmac(kRegion, Data(service.utf8))
        return Self.hmac(kService, Data("aws4_request".utf8))
    }

    private static func hmac(_ key: Data, _ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func hmacHex(_ key: Data, _ string: String) -> String {
        hmac(key, Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// RFC 3986 percent-encoding with uppercase hex, matching SigV4's rules.
    static func uriEncode(_ string: String, encodeSlash: Bool) -> String {
        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var result = ""
        for byte in string.utf8 {
            let scalar = Character(UnicodeScalar(byte))
            if unreserved.contains(scalar) || (!encodeSlash && scalar == "/") {
                result.append(scalar)
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    private static func dates(_ now: Date) -> (amz: String, stamp: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amz = formatter.string(from: now)
        return (amz, String(amz.prefix(8)))
    }
}
