import Foundation
import Network

/// Minimal shared path monitor so playback can tell whether it is on
/// cellular. Wi-Fi and wired paths keep the user's Audio Quality setting.
final class NetworkStatus: @unchecked Sendable {
    static let shared = NetworkStatus()

    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cl0udly.Apollo.network")
    private var cellular = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let value = path.usesInterfaceType(.cellular)
            self.lock.lock()
            self.cellular = value
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    var isCellular: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cellular
    }
}
