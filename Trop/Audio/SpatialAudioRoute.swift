import AVFoundation
import Foundation

/// Cached answer to "is a spatial-capable output connected?", used by the
/// Automatic Dolby Atmos mode. Playback actors read it while resolving, so the
/// value must be cheap and thread-safe.
final class SpatialAudioRoute: @unchecked Sendable {
    static let shared = SpatialAudioRoute()

    private let lock = NSLock()
    private var capable = false
    private var observer: NSObjectProtocol?

    private init() {
        capable = Self.detect()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    var isSpatialCapable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return capable
    }

    private func refresh() {
        let value = Self.detect()
        lock.lock()
        capable = value
        lock.unlock()
    }

    private static func detect() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .airPlay, .bluetoothA2DP, .bluetoothLE, .headphones, .usbAudio, .HDMI:
                return true
            default:
                return false
            }
        }
    }
}
