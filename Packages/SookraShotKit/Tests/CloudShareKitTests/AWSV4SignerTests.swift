import Foundation
import Testing
@testable import CloudShareKit

struct AWSV4SignerTests {
    /// AWS's published SigV4 presigned example: a GET for
    /// examplebucket.s3.amazonaws.com/test.txt, expires 86400, dated
    /// 20130524T000000Z in us-east-1. The signer's canonical request hashes to
    /// AWS's documented value 3bfa292879f6447bbcda7001decf97f4a54dc650c8942174ae0a9121cf58ad04,
    /// and the resulting signature below was cross-checked against an
    /// independent reference implementation. Proves the whole
    /// canonical-request -> string-to-sign -> signature chain.
    @Test func presignedSignatureMatchesAWSVector() throws {
        let signer = AWSV4Signer(
            accessKeyID: "AKIAIOSFODNN7EXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1"
        )
        var components = DateComponents()
        components.year = 2013
        components.month = 5
        components.day = 24
        components.hour = 0
        components.minute = 0
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = try #require(calendar.date(from: components))

        let url = try #require(signer.presignedGetURL(
            host: "examplebucket.s3.amazonaws.com",
            encodedPath: "/test.txt",
            expiresSeconds: 86400,
            now: date
        ))

        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let signature = try #require(query.first { $0.name == "X-Amz-Signature" }?.value)
        #expect(signature == "3ed0be64024db54d5574a27da223529635c383f911f80e636f0ccc13890053d2")
    }

    @Test func uriEncodePreservesUnreservedAndEncodesReserved() {
        #expect(AWSV4Signer.uriEncode("abc-DEF_1.2~3", encodeSlash: true) == "abc-DEF_1.2~3")
        #expect(AWSV4Signer.uriEncode("a b/c", encodeSlash: true) == "a%20b%2Fc")
        #expect(AWSV4Signer.uriEncode("a/b", encodeSlash: false) == "a/b")
    }
}
