#if DEBUG
import Foundation

/// The tour's log, `Documents/review-log.txt`: each step with its time and every error the recorder
/// reports, so a take on a device can be followed afterwards (`devicectl device copy from`).
nonisolated enum DemoLog {
    static let url = URL.documentsDirectory.appending(path: "review-log.txt")
    private static let lock = NSLock()
    private static let time = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func write(_ message: String) {
        let line = Data("\(time.format(.now)) \(message)\n".utf8)
        lock.withLock {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url)
            }
        }
    }

    static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
#endif
