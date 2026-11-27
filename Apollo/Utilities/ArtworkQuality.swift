import Foundation

enum ArtworkQuality {
    static func pixelWidth(of url: URL?) -> Int {
        guard let url else { return 0 }
        let value = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""

        if host.contains("scdn.co") { return 640 }
        if value.contains("maxresdefault") { return 1280 }
        if value.contains("sddefault") { return 640 }
        if value.contains("hqdefault") { return 480 }

        if let match = value.range(of: #"\d{2,5}x\d{2,5}"#, options: .regularExpression) {
            let size = value[match]
            if let width = size.split(separator: "x").first, let pixels = Int(width) {
                return pixels
            }
        }
        if let match = value.range(of: #"=w\d+"#, options: .regularExpression),
           let pixels = Int(value[match].dropFirst(2)) {
            return pixels
        }
        return 0
    }

    static func better(_ current: URL?, than candidate: URL?) -> URL? {
        let currentWidth = pixelWidth(of: current)
        let candidateWidth = pixelWidth(of: candidate)
        if candidateWidth > currentWidth { return candidate }
        return current
    }
}
