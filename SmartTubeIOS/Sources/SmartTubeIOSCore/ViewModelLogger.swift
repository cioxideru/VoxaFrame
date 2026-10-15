import Foundation
import os

// MARK: - ViewModelLogger
//
// Foundation-only `os.Logger` wrapper used across the app. Messages are logged
// with `.public` privacy and stay on the device; nothing is forwarded anywhere.
// Use errorSummary and urlHost instead of interpolating errors or URLs into messages.

package struct ViewModelLogger: Sendable {
    private let logger: Logger

    package init(subsystem: String = appSubsystem, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    package static func urlHost(_ url: URL?) -> String {
        guard let host = url?.host(), !host.isEmpty else { return "none" }
        return host
    }

    package static func errorSummary(_ error: (any Error)?) -> String {
        guard let error else { return "none" }
        let nsError = error as NSError
        let failingURL =
            nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            ?? (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap { URL(string: $0) }
        return "domain=\(nsError.domain) code=\(nsError.code) host=\(urlHost(failingURL))"
    }

    package func notice(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.notice("\(msg, privacy: .public)")
    }

    package func error(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.error("\(msg, privacy: .public)")
    }

    package func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.debug("\(msg, privacy: .public)")
    }
}
