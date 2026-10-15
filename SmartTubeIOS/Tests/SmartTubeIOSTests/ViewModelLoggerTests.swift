import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("ViewModelLogger privacy")
struct ViewModelLoggerTests {
    @Test("URL logging excludes credentials, signed paths, queries and fragments")
    func urlIncludesOnlyHost() throws {
        let url = try #require(URL(string: "https://user:password@cdn.example.com/signed/secret?sig=token#private"))

        #expect(ViewModelLogger.urlHost(url) == "cdn.example.com")
    }

    @Test("Missing, local and relative URLs do not disclose paths")
    func urlsWithoutHosts() throws {
        #expect(ViewModelLogger.urlHost(nil) == "none")
        #expect(ViewModelLogger.urlHost(URL(fileURLWithPath: "/private/video.mp4")) == "none")
        #expect(ViewModelLogger.urlHost(try #require(URL(string: "segment.ts?sig=token"))) == "none")
    }

    @Test("Error logging excludes descriptions, nested errors and arbitrary user info")
    func errorIncludesOnlyDomainCodeAndHost() throws {
        let url = try #require(URL(string: "https://cdn.example.com/signed/secret?sig=token"))
        let error = NSError(
            domain: NSURLErrorDomain, code: -1001,
            userInfo: [
                NSURLErrorFailingURLErrorKey: url,
                NSLocalizedDescriptionKey: "Failed to fetch \(url)",
                NSLocalizedFailureReasonErrorKey: "private reason",
                NSUnderlyingErrorKey: NSError(
                    domain: "Nested", code: 42, userInfo: [NSLocalizedDescriptionKey: url.absoluteString]),
                "token": "private token",
            ])

        #expect(ViewModelLogger.errorSummary(error) == "domain=\(NSURLErrorDomain) code=-1001 host=cdn.example.com")
    }

    @Test("A failing URL stored as a string is reduced to its host")
    func failingURLString() {
        let error = NSError(
            domain: NSURLErrorDomain, code: -1002,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "https://cdn.example.com/secret?sig=token"])

        #expect(ViewModelLogger.errorSummary(error) == "domain=\(NSURLErrorDomain) code=-1002 host=cdn.example.com")
    }

    @Test("Errors without URLs and absent errors have safe summaries")
    func absentErrorDetails() {
        #expect(ViewModelLogger.errorSummary(NSError(domain: "Player", code: 42)) == "domain=Player code=42 host=none")
        #expect(ViewModelLogger.errorSummary(nil) == "none")
    }
}
