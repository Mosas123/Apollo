import Foundation

@main
enum ApoloOfflineRecoveryPolicyChecks {
    static func main() {
        assert(ApoloOfflineRecoveryPolicy.shouldHold(
            isFiniteAudio: true, isHTTPSource: true, networkUnavailable: true
        ))
        assert(!ApoloOfflineRecoveryPolicy.shouldHold(
            isFiniteAudio: false, isHTTPSource: true, networkUnavailable: true
        ))
        assert(!ApoloOfflineRecoveryPolicy.shouldHold(
            isFiniteAudio: true, isHTTPSource: false, networkUnavailable: true
        ))
        assert(!ApoloOfflineRecoveryPolicy.shouldHold(
            isFiniteAudio: true, isHTTPSource: true, networkUnavailable: false
        ))

        func retry(
            sameSelection: Bool = true,
            sameEngineGeneration: Bool = true,
            networkAvailable: Bool = true,
            desiredPlaying: Bool = true,
            explicitlyPaused: Bool = false,
            audioInterrupted: Bool = false,
            audioActivationPending: Bool = false
        ) -> Bool {
            ApoloOfflineRecoveryPolicy.mayResume(
                sameSelection: sameSelection,
                sameEngineGeneration: sameEngineGeneration,
                networkAvailable: networkAvailable,
                desiredPlaying: desiredPlaying,
                explicitlyPaused: explicitlyPaused,
                audioInterrupted: audioInterrupted,
                audioActivationPending: audioActivationPending
            )
        }

        assert(retry())
        assert(!retry(sameSelection: false))
        assert(!retry(sameEngineGeneration: false))
        assert(!retry(networkAvailable: false))
        assert(!retry(desiredPlaying: false))
        assert(!retry(explicitlyPaused: true))
        assert(!retry(audioInterrupted: true))
        assert(!retry(audioActivationPending: true))
        print("Apolo offline recovery policy checks passed")
    }
}
