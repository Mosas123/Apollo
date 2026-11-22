import Foundation

@main
struct FileLogLaunchChecks {
    static func main() throws {
        guard let url = FileLog.shared.fileURL else {
            fatalError("Documents/log.txt unavailable in macOS test runner")
        }
        // Only the temporary runner's Documents path is touched; restore any
        // pre-existing file after checking the actual production FileLog type.
        let previous = try? Data(contentsOf: url)
        defer {
            if let previous {
                try? previous.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let staleMarker = "STALE_FROM_PREVIOUS_PROCESS"
        try Data("\(staleMarker)\n".utf8).write(to: url, options: .atomic)

        let lazy = CommandLine.arguments.contains("--implicit")
        if !lazy {
            FileLog.shared.beginNewLaunch()
            let reset = try String(contentsOf: url, encoding: .utf8)
            precondition(reset.isEmpty, "Log was not cleared at process start")
        }

        FileLog.shared.append("launchTest", "INFO", "CURRENT_PROCESS")
        // Serial queue.sync is a fence for the async file append.
        FileLog.shared.beginNewLaunch()
        let current = try String(contentsOf: url, encoding: .utf8)
        precondition(current.contains("CURRENT_PROCESS"), "Current session line missing")
        precondition(!current.contains(staleMarker), "Previous session leaked into new log")

        // Multiple app/window/foreground calls must NOT clear the active log.
        FileLog.shared.beginNewLaunch()
        let kept = try String(contentsOf: url, encoding: .utf8)
        precondition(kept == current, "Second session init cleared current log")

        print("FileLog \(lazy ? "implicit" : "explicit") startup reset and reuse OK")
    }
}
