import Foundation
import os

// MARK: - ViewModelLogger
//
// Foundation-only `os.Logger` wrapper used across the app. Messages are logged
// with `.public` privacy and stay on the device; nothing is forwarded anywhere.

package struct ViewModelLogger: Sendable {
    private let logger: Logger

    package init(subsystem: String = appSubsystem, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
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
