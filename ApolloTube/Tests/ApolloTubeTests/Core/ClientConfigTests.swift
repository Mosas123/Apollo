//
//  ClientConfigTests.swift
//  ApolloTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Testing

@testable import ApolloTube

@Suite("Clients and config")
struct ClientConfigTests {
    @Test("Built-in client presets")
    func presets() {
        #expect(YouTubeClient.webRemix.clientName == "WEB_REMIX")
        #expect(YouTubeClient.webRemix.loginSupported == true)
        #expect(YouTubeClient.web.clientName == "WEB")
        #expect(YouTubeClient.iOS.clientName == "IOS")
    }

    @Test("Config presets match their service")
    func configPresets() {
        #expect(ApolloTubeConfig.music.service == .music)
        #expect(ApolloTubeConfig.music.defaultClient.clientName == "WEB_REMIX")
        #expect(ApolloTubeConfig.youtube.service == .youtube)
        #expect(ApolloTubeConfig.youtube.defaultClient.clientName == "WEB")
    }

    @Test("Defaults")
    func defaults() {
        #expect(YouTubeLocale.default.gl == "US")
        #expect(YouTubeLocale.default.hl == "en")
        #expect(AuthState.guest.cookies.isEmpty)
        #expect(AuthState.guest.sapisid == nil)
        #expect(AuthState.guest.visitorData == nil)
        #expect(ApolloTubeVersion.current == "0.0.8")
    }
}
