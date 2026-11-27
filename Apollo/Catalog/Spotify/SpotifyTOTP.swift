import CryptoKit
import Foundation

/// Spotify's anonymous web-player token needs a TOTP derived from the
/// versioned secret list the web player ships. The list rotates; the remote
/// copy is preferred, with an offline fallback so a cold start still works.
actor SpotifyTOTPSecrets {
    static let shared = SpotifyTOTPSecrets()

    private let endpoint = URL(
        string: "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json"
    )!
    private let ttl: TimeInterval = 6 * 60 * 60
    private var cached: [Int: [Int]]?
    private var cachedAt: Date?

    private static let fallback: [Int: [Int]] = [
        59: [
            123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86,
            63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72
        ],
        60: [
            79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85,
            122, 63, 91, 64, 87, 87
        ],
        61: [
            44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76,
            94, 102, 43, 69, 49, 120, 118, 80, 64, 78
        ]
    ]

    func secrets() async -> [Int: [Int]] {
        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < ttl {
            return cached
        }

        if let remote = await fetch() {
            cached = remote
            cachedAt = Date()
            return remote
        }

        return cached ?? Self.fallback
    }

    private func fetch() async -> [Int: [Int]]? {
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let raw = try JSONDecoder().decode([String: [Int]].self, from: data)
            var result: [Int: [Int]] = [:]
            for (key, values) in raw {
                if let version = Int(key) { result[version] = values }
            }
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }
}

enum SpotifyTOTP {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func code(at date: Date = Date()) async -> (code: String, version: Int)? {
        let secrets = await SpotifyTOTPSecrets.shared.secrets()
        guard let version = secrets.keys.max(),
              let values = secrets[version],
              !values.isEmpty else {
            return nil
        }

        let secret = computeSecret(values)
        guard let key = base32Decode(secret) else { return nil }
        let counter = UInt64(date.timeIntervalSince1970) / 30
        return (hotp(key: key, counter: counter), version)
    }

    private static func computeSecret(_ values: [Int]) -> String {
        let transformed = values.enumerated().map { index, value in
            value ^ ((index % 33) + 9)
        }
        let joined = transformed.map(String.init).joined()

        var bytes: [UInt8] = []
        bytes.reserveCapacity(joined.utf8.count)
        for scalar in joined.unicodeScalars where scalar.value <= 0x7F {
            bytes.append(UInt8(scalar.value))
        }
        return base32Encode(Data(bytes))
    }

    private static func hotp(key: Data, counter: UInt64) -> String {
        var bigEndianCounter = counter.bigEndian
        let message = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: message,
            using: SymmetricKey(data: key)
        )
        let bytes = Array(mac)
        guard bytes.count >= 20 else { return "000000" }

        let offset = Int(bytes[19] & 0x0F)
        guard offset + 3 < bytes.count else { return "000000" }

        let value = (UInt32(bytes[offset] & 0x7F) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])

        return String(format: "%06d", Int(value % 1_000_000))
    }

    private static func base32Encode(_ data: Data) -> String {
        var result = ""
        var bits = 0
        var value = 0

        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                result.append(alphabet[(value >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 {
            result.append(alphabet[(value << (5 - bits)) & 31])
        }
        return result
    }

    private static func base32Decode(_ string: String) -> Data? {
        var bits = 0
        var value = 0
        var output = Data()

        for character in string.uppercased().replacingOccurrences(of: "=", with: "") {
            guard let index = alphabet.firstIndex(of: character) else { continue }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return output.isEmpty ? nil : output
    }
}
