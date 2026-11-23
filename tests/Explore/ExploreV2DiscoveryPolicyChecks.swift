import Foundation

@main
struct ExploreV2DiscoveryPolicyChecks {
    static func main() {
        let seeds = ExploreV2DiscoveryPolicy.artistSeeds([
            nil, "", " ", "KAROL G", "karol g", "  Ella Langley  ",
            "Omar Courtz", "Bad Bunny", "Rosalía", "Beyoncé", "Too Many"
        ])
        precondition(seeds == [
            "KAROL G", "Ella Langley", "Omar Courtz",
            "Bad Bunny", "Rosalía", "Beyoncé"
        ])
        precondition(ExploreV2DiscoveryPolicy.artistSeeds([
            "Beyonce", "Beyoncé"
        ]).count == 1)
        precondition(ExploreV2DiscoveryPolicy.artistSeeds([
            String(repeating: "A", count: 121)
        ]).isEmpty)

        precondition(ExploreV2DiscoveryPolicy.matchesArtist(
            "KAROL G", selected: "Karol G"
        ))
        precondition(ExploreV2DiscoveryPolicy.matchesArtist(
            "Ella Langley feat Guest", selected: "Ella Langley"
        ))
        precondition(ExploreV2DiscoveryPolicy.matchesArtist(
            "Rosalia & Guest", selected: "Rosalía"
        ))
        precondition(!ExploreV2DiscoveryPolicy.matchesArtist(
            "Ella Fitzgerald", selected: "Ella Langley"
        ))
        precondition(!ExploreV2DiscoveryPolicy.matchesArtist(
            "KAROL", selected: "KAROL G"
        ))
        precondition(!ExploreV2DiscoveryPolicy.matchesArtist(
            "Bad", selected: " "
        ))
        precondition(ExploreV2DiscoveryPolicy.maximumAddonInstallations <= 3)
        precondition(ExploreV2DiscoveryPolicy.maximumVisibleTracks <= 24)
        print("Explore V2 artist seeds, identity filter and search budgets passed")
    }
}
