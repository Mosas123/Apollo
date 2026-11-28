import Foundation

@main
struct MusicVersionPolicyChecks {
    static func main() {
        precondition(MusicVersionPolicy.version(in: "Song (Clean)") == .clean)
        precondition(MusicVersionPolicy.version(in: "Song [Censored]") == .clean)
        precondition(MusicVersionPolicy.version(in: "Song - Clean") == .clean)
        precondition(MusicVersionPolicy.version(in: "Song (Explicit)") == .explicit)
        precondition(MusicVersionPolicy.version(in: "Song - Dirty") == .explicit)
        precondition(MusicVersionPolicy.version(in: "Song (Official Audio)") == .unknown)
        precondition(MusicVersionPolicy.version(in: "Clean Bandit - Rather Be") == .unknown)
        precondition(MusicVersionPolicy.version(in: "Cleanin' Out My Closet") == .unknown)

        precondition(!MusicVersionPolicy.isCompatible(candidateTitle: "Song (Clean)", requestedExplicit: true))
        precondition(MusicVersionPolicy.isCompatible(candidateTitle: "Song (Clean)", requestedExplicit: false))
        precondition(MusicVersionPolicy.isCompatible(candidateTitle: "Song (Explicit)", requestedExplicit: true))
        precondition(!MusicVersionPolicy.isCompatible(candidateTitle: "Song (Explicit)", requestedExplicit: false))
        precondition(MusicVersionPolicy.isCompatible(candidateTitle: "Song (Official Audio)", requestedExplicit: true))
        precondition(MusicVersionPolicy.isCompatible(candidateTitle: "Song (Official Audio)", requestedExplicit: false))

        precondition(MusicVersionPolicy.scoreBonus(candidateTitle: "Song (Explicit)", requestedExplicit: true) > 0)
        precondition(MusicVersionPolicy.scoreBonus(candidateTitle: "Song (Clean)", requestedExplicit: true) == 0)
        precondition(MusicVersionPolicy.scoreBonus(candidateTitle: "Song (Clean)", requestedExplicit: false) > 0)

        print("MusicVersionPolicyChecks passed")
    }
}
