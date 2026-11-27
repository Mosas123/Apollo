//
//  MusixmatchProvider.swift
//  Apollo
//
//  Created by 686udjie on 16/07/2026.
//

// https://github.com/spicetify/cli/blob/main/CustomApps/lyrics-plus/ProviderMusixmatch.js

import Foundation
import Synchronization

private struct MusixmatchTokenState: Sendable {
    var token: String?
    var fetchedAt: Date?
}

/// Thread-safe cache for the Musixmatch guest token. Tokens are short-lived,
/// so we re-fetch once they're older than `ttl` instead of caching forever.
private enum MusixmatchTokenCache {
    static let state = Mutex(MusixmatchTokenState())
    static let ttl: TimeInterval = 600
}

struct MusixmatchProvider: LyricsProvider {
    let id = "musixmatch"
    let name = "Musixmatch"

    private let baseURL = "https://apic-appmobile.musixmatch.com/ws/1.1/macro.subtitles.get"
    private let tokenURL = "https://apic-appmobile.musixmatch.com/ws/1.1/token.get?app_id=mac-ios-v2.0&"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        let token = try await fetchToken()
        var components = URLComponents(string: baseURL)!
        let dur = Int(query.duration)
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "namespace", value: "lyrics_richsynched"),
            URLQueryItem(name: "subtitle_format", value: "mxm"),
            URLQueryItem(name: "app_id", value: "mac-ios-v2.0"),
            URLQueryItem(name: "q_track", value: query.title),
            URLQueryItem(name: "q_artist", value: query.artist),
            URLQueryItem(name: "q_artists", value: query.artist),
            URLQueryItem(name: "q_album", value: query.album ?? ""),
            URLQueryItem(name: "q_duration", value: String(dur)),
            URLQueryItem(name: "f_subtitle_length", value: String(dur)),
            URLQueryItem(name: "usertoken", value: token),
            URLQueryItem(name: "part", value: "track_lyrics_translation_status,track_structure,track_performer_tagging")
        ]

        guard let url = components.url else { throw LyricsError.invalidURL }
        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        let json = try await LyricsHTTP.getJSON(request)
        return try parse(json, query: query)
    }

    // MARK: - Token

    private func fetchToken() async throws -> String {
        let cached = MusixmatchTokenCache.state.withLock { $0 }
        if let token = cached.token, let fetchedAt = cached.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < MusixmatchTokenCache.ttl {
            return token
        }
        guard let url = URL(string: tokenURL) else { throw LyricsError.invalidURL }
        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        let json = try await LyricsHTTP.getJSON(request)
        guard let message = json["message"] as? [String: Any],
              let body = message["body"] as? [String: Any],
              let token = body["user_token"] as? String, !token.isEmpty else {
            throw LyricsError.notFound
        }
        MusixmatchTokenCache.state.withLock { $0 = MusixmatchTokenState(token: token, fetchedAt: Date()) }
        return token
    }

    // MARK: - Parsing

    private func parse(_ json: [String: Any], query: LyricsQuery) throws -> [LyricLine] {
        guard let message = json["message"] as? [String: Any],
              let body = message["body"] as? [String: Any],
              let macro = body["macro_calls"] as? [String: Any] else {
            throw LyricsError.notFound
        }

        // Matcher must ==
        guard let matcher = macro["matcher.track.get"] as? [String: Any],
              let mMessage = matcher["message"] as? [String: Any],
              let mHeader = mMessage["header"] as? [String: Any],
              (mHeader["status_code"] as? Int) == 200 else {
            throw LyricsError.notFound
        }

        let mBody = mMessage["body"] as? [String: Any] ?? [:]
        let track = mBody["track"] as? [String: Any] ?? [:]
        guard LyricsMatch.accepts(query, title: track["track_name"] as? String,
                                  artists: [track["artist_name"] as? String ?? ""],
                                  duration: track["track_length"] as? Double) else { throw LyricsError.notFound }
        if track["instrumental"] as? Bool == true {
            return [LyricLine(text: "♪ Instrumental ♪", startTime: nil)]
        }

        // Restricted lyrics cannot be shown
        if let lyricsCall = macro["track.lyrics.get"] as? [String: Any],
           let lMessage = lyricsCall["message"] as? [String: Any],
           let lBody = lMessage["body"] as? [String: Any],
           let lyrics = lBody["lyrics"] as? [String: Any],
           (lyrics["restricted"] as? Bool) == true {
            throw LyricsError.notFound
        }

        // Synced
        if let subsCall = macro["track.subtitles.get"] as? [String: Any],
           let sMessage = subsCall["message"] as? [String: Any],
           let sBody = sMessage["body"] as? [String: Any],
           let subList = sBody["subtitle_list"] as? [[String: Any]],
           let first = subList.first,
           let subtitle = first["subtitle"] as? [String: Any],
           let bodyStr = subtitle["subtitle_body"] as? String,
           let data = bodyStr.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let lines = arr.compactMap { item -> LyricLine? in
                guard let text = item["text"] as? String,
                      !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                let time = (item["time"] as? [String: Any])?["total"] as? Double ?? 0
                return LyricLine(text: text, startTime: time > 0 ? time : nil)
            }
            if !lines.isEmpty { return lines }
        }

        // Unsynced
        if let lyricsCall = macro["track.lyrics.get"] as? [String: Any],
           let lMessage = lyricsCall["message"] as? [String: Any],
           let lBody = lMessage["body"] as? [String: Any],
           let lyrics = lBody["lyrics"] as? [String: Any],
           let bodyStr = lyrics["lyrics_body"] as? String {
            let lines = LyricsText.plainLines(bodyStr)
            if !lines.isEmpty { return lines }
        }

        throw LyricsError.notFound
    }

    // MARK: - Headers

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("apic-appmobile.musixmatch.com", forHTTPHeaderField: "Host")
        request.setValue("apic-appmobile.musixmatch.com", forHTTPHeaderField: "authority")
        request.setValue("x-mxm-token-guid=", forHTTPHeaderField: "X-Cookie")
        request.setValue("10.1.1", forHTTPHeaderField: "x-mxm-app-version")
        request.setValue("Musixmatch/2025120901 CFNetwork/3860.300.31 Darwin/25.2.0", forHTTPHeaderField: "X-User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }
}
