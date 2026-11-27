//
//  CommentsService.swift
//  Apollo
//
//  Created by 686udjie on 05/11/2026.
//

@preconcurrency import SwiftyTube
import Foundation

enum CommentsError: LocalizedError {
    case disabled
    case empty
    case rejected(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return NSLocalizedString("Comments are disabled for this song", comment: "")
        case .empty:
            return NSLocalizedString("No comments yet", comment: "")
        case .rejected(let message):
            return message
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Fetches YouTube comment threads via InnerTube `/next` using the WEB client.
/// YT Music's WEB_REMIX client does not return the comments section.
actor CommentsService {
    static let shared = CommentsService()

    private let musicClient = InnerTubeClient.apolloShared
    private let youtubeClient = InnerTubeClient(config: .youtube)

    private var initialCache: [String: (page: CommentsPage, date: Date)] = [:]
    private let initialTTL: TimeInterval = 300

    func loadInitial(videoId: String) async throws -> CommentsPage {
        if let cached = initialCache[videoId],
           Date().timeIntervalSince(cached.date) < initialTTL {
            return cached.page
        }
        let token = try await initialCommentsToken(videoId: videoId)
        let page = try await fetchPage(continuation: token)
        if page.items.isEmpty, page.nextPageToken == nil {
            throw CommentsError.disabled
        }
        initialCache[videoId] = (page, Date())
        if initialCache.count > 20 {
            initialCache = initialCache.filter { Date().timeIntervalSince($0.value.date) < initialTTL }
        }
        return page
    }

    func loadPage(continuation: String) async throws -> CommentsPage {
        try await fetchPage(continuation: continuation)
    }

    func loadReplies(continuation: String) async throws -> CommentRepliesPage {
        let json = try await fetchContinuationJSON(continuation)
        return CommentsParser.parseRepliesPage(json)
    }

    func performCommentAction(action: String) async throws -> Bool {
        do {
            await syncAuth(into: musicClient)
            let json = try await musicClient.performCommentAction(action: action, client: .web).value
            return Self.voteSucceeded(json)
        } catch {
            await syncAuth(into: youtubeClient)
            do {
                let json = try await youtubeClient.performCommentAction(action: action, client: .web).value
                return Self.voteSucceeded(json)
            } catch {
                throw CommentsError.underlying(error)
            }
        }
    }

    /// Posts a top-level comment with the server-issued params from the
    /// comments header. HTTP errors fall back from the music host to www;
    /// a 200 carrying `showErrorAction` is a real rejection, not retried.
    func postComment(params: String, text: String) async throws {
        let json: [String: Any]
        do {
            await syncAuth(into: musicClient)
            json = try await musicClient.createComment(params: params, text: text, client: .web).value
        } catch {
            await syncAuth(into: youtubeClient)
            do {
                json = try await youtubeClient.createComment(params: params, text: text, client: .web).value
            } catch {
                throw CommentsError.underlying(error)
            }
        }
        if let message = Self.postFailureMessage(json) {
            throw CommentsError.rejected(message)
        }
    }

    func updateComment(params: String, text: String) async throws {
        let json: [String: Any]
        do {
            await syncAuth(into: musicClient)
            json = try await musicClient.updateComment(params: params, text: text, client: .web).value
        } catch {
            await syncAuth(into: youtubeClient)
            do {
                json = try await youtubeClient.updateComment(params: params, text: text, client: .web).value
            } catch {
                throw CommentsError.underlying(error)
            }
        }
        if let message = Self.postFailureMessage(json) {
            throw CommentsError.rejected(message)
        }
    }

    // MARK: - Report flow

    /// Opens the comment abuse-report panel: the reason list plus the
    /// flow-state entity every later `/flow` call must echo back. Works
    /// signed-out too — YouTube gates the actual submission server-side.
    func loadReportPanel(params: String) async throws -> CommentsParser.CommentReportPanel {
        let json = try await reportPOST { client in
            try await client.abuseReportPanel(params: params, client: .web)
        }
        guard let panel = CommentsParser.parseReportPanel(json.value) else {
            throw CommentsError.rejected(
                NSLocalizedString("Couldn't load report options", comment: "")
            )
        }
        return panel
    }

    /// Sends one `/flow` advance (reason → details → confirmation) and
    /// classifies the response: new steps, the server's failure toast, or
    /// a no-op 200.
    func advanceReportFlow(
        flowState: TubeJSON,
        flowStateEntityKey: String,
        flowId: String,
        targetId: String
    ) async throws -> CommentsParser.CommentReportFlowUpdate {
        let json = try await reportPOST { client in
            try await client.abuseReportFlow(
                flowState: flowState,
                flowStateEntityKey: flowStateEntityKey,
                flowId: flowId,
                targetId: targetId,
                client: .web
            )
        }
        return CommentsParser.parseReportFlowUpdate(json.value)
    }

    private static func postFailureMessage(_ json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        guard let actions = json["actions"] as? [[String: Any]],
              let first = actions.first,
              let showError = first["showErrorAction"] as? [String: Any],
              let errorMessage = showError["errorMessage"] as? [String: Any],
              let renderer = errorMessage["messageRenderer"] as? [String: Any],
              let text = renderer["text"] as? [String: Any] else { return nil }
        if let simple = text["simpleText"] as? String { return simple }
        if let runs = text["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }

    private static func voteSucceeded(_ json: [String: Any]) -> Bool {
        let results = json["actionResults"] as? [[String: Any]]
        return results?.first?["status"] as? String == "STATUS_SUCCEEDED"
    }

    // MARK: - Private

    private func initialCommentsToken(videoId: String) async throws -> String {
        // Prefer the music host (same-origin for YTM session), then fall back to www.
        if let token = await commentsToken(videoId: videoId, client: musicClient) {
            return token
        }
        if let token = await commentsToken(videoId: videoId, client: youtubeClient) {
            return token
        }
        throw CommentsError.disabled
    }

    private func commentsToken(videoId: String, client: InnerTubeClient) async -> String? {
        do {
            await syncAuth(into: client)
            let json = try await client.next(videoId: videoId, client: .web).value
            return CommentsParser.findInitialCommentsToken(in: json)
        } catch {
            return nil
        }
    }

    private func fetchPage(continuation: String) async throws -> CommentsPage {
        let json = try await fetchContinuationJSON(continuation)
        return CommentsParser.parseCommentsPage(json)
    }

    // MARK: - Report helpers

    /// POSTs an abuse-report call music-host first with www fallback (same
    /// shape as the other comment mutations). A structured server rejection
    /// (400 `error.message`) is surfaced verbatim; everything else falls
    /// back to www before being wrapped.
    private func reportPOST(
        _ call: @escaping (InnerTubeClient) async throws -> TubeJSON
    ) async throws -> TubeJSON {
        do {
            await syncAuth(into: musicClient)
            return try await call(musicClient)
        } catch {
            await syncAuth(into: youtubeClient)
            do {
                return try await call(youtubeClient)
            } catch {
                if let message = Self.serverMessage(from: error) {
                    throw CommentsError.rejected(message)
                }
                throw CommentsError.underlying(error)
            }
        }
    }

    /// Pulls `error.message` out of a non-2xx InnerTube body.
    private static func serverMessage(from error: Error) -> String? {
        guard case InnerTubeError.httpError(_, let data) = error,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObject = json["error"] as? [String: Any],
              let message = errorObject["message"] as? String else { return nil }
        return message
    }

    private func fetchContinuationJSON(_ continuation: String) async throws -> [String: Any] {
        // Continuations are host-agnostic enough that music-first still works.
        let json: [String: Any]
        do {
            await syncAuth(into: musicClient)
            json = try await musicClient.next(continuation: continuation, client: .web).value
        } catch {
            await syncAuth(into: youtubeClient)
            do {
                json = try await youtubeClient.next(continuation: continuation, client: .web).value
            } catch {
                throw CommentsError.underlying(error)
            }
        }
        return json
    }

    private func syncAuth(into client: InnerTubeClient) async {
        let store = CookieStore()
        await client.loadState(from: store)
        await client.syncApolloLocale()
    }
}
