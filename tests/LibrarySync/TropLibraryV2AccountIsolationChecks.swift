import Foundation

@main
enum TropLibraryV2AccountIsolationChecks {
    static func main() {
        let key = TropLibraryV2AccountIsolation.preferenceKey
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(false, forKey: key)
        precondition(!TropLibraryV2AccountIsolation.isEnabled)
        defaults.set(true, forKey: key)
        precondition(TropLibraryV2AccountIsolation.isEnabled)
        defaults.set(false, forKey: key)
        precondition(!TropLibraryV2AccountIsolation.isEnabled)
        print("Trop Library V2 account isolation policy checks passed")
    }
}
