import Foundation

@main
struct PlaybackEventPolicyChecks {
    static func main() {
        duplicatePlayIsSuppressed()
        terminalIsSingleUse()
        pauseResumeIsBalanced()
        saveIsDeduplicated()
        resetStartsFresh()
        print("PlaybackEventPolicyChecks passed")
    }

    private static func duplicatePlayIsSuppressed() {
        var policy = PlaybackEventPolicy()
        precondition(policy.begin("track-a"))
        precondition(!policy.begin("track-a"))
        precondition(policy.begin("track-b"))
        precondition(policy.begin("track-a"))
    }

    private static func terminalIsSingleUse() {
        var policy = PlaybackEventPolicy()
        precondition(policy.begin("a"))
        precondition(policy.finish("a", kind: .skip))
        precondition(!policy.finish("a", kind: .complete))
        precondition(!policy.pause("a"))
        // A later replay of the same selection is a new event.
        precondition(policy.begin("a"))
        precondition(policy.finish("a", kind: .complete))
    }

    private static func pauseResumeIsBalanced() {
        var policy = PlaybackEventPolicy()
        precondition(policy.begin("a"))
        precondition(policy.pause("a"))
        precondition(!policy.pause("a"))
        precondition(policy.resume("a"))
        precondition(!policy.resume("a"))
        precondition(!policy.pause("b"))
        precondition(policy.finish("a", kind: .complete))
    }

    private static func saveIsDeduplicated() {
        var policy = PlaybackEventPolicy()
        precondition(policy.save("song-a"))
        precondition(!policy.save("song-a"))
        precondition(policy.save("song-b"))
    }

    private static func resetStartsFresh() {
        var policy = PlaybackEventPolicy()
        precondition(policy.begin("a"))
        precondition(policy.save("a"))
        policy.reset()
        precondition(policy.begin("a"))
        precondition(policy.save("a"))
    }
}
