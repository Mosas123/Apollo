import Foundation

struct PodcastEpisode: Hashable, Sendable {
    let title: String
    let guid: String?
    let duration: Int?
    let publishedAt: Date?
    let audioURL: URL
    let mimeType: String?
}

struct PodcastFeedContent: Sendable {
    let title: String
    let author: String?
    let artworkURL: URL?
    let episodes: [PodcastEpisode]
}

actor PodcastRSSFeedLoader {
    static let shared = PodcastRSSFeedLoader()

    private struct Entry {
        let content: PodcastFeedContent?
        let at: Date
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 60 * 60

    func content(for feedURL: URL) async -> PodcastFeedContent? {
        let key = feedURL.absoluteString
        if let entry = cache[key], Date().timeIntervalSince(entry.at) < ttl {
            return entry.content
        }

        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 20
        request.setValue(
            "Apollo/0.14.0 (Podcast RSS reader; com.cl0udly.Apollo)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            cache[key] = Entry(content: nil, at: Date())
            return nil
        }

        let parser = PodcastRSSParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse(), !parser.episodes.isEmpty else {
            cache[key] = Entry(content: nil, at: Date())
            return nil
        }

        let content = PodcastFeedContent(
            title: parser.channelTitle ?? feedURL.host ?? "Podcast",
            author: parser.channelAuthor,
            artworkURL: parser.channelArtworkURL,
            episodes: parser.episodes
        )
        cache[key] = Entry(content: content, at: Date())
        return content
    }
}

private final class PodcastRSSParser: NSObject, XMLParserDelegate {
    private(set) var channelTitle: String?
    private(set) var channelAuthor: String?
    private(set) var channelArtworkURL: URL?
    private(set) var episodes: [PodcastEpisode] = []

    private var currentText = ""
    private var inItem = false
    private var itemTitle: String?
    private var itemGUID: String?
    private var itemDuration: Int?
    private var itemDate: Date?
    private var itemAudioURL: URL?
    private var itemMimeType: String?

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss Z"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        currentText = ""

        if name == "item" {
            inItem = true
            itemTitle = nil
            itemGUID = nil
            itemDuration = nil
            itemDate = nil
            itemAudioURL = nil
            itemMimeType = nil
            return
        }

        if !inItem, name == "image", let raw = attributeDict["href"],
           let url = URL(string: raw) {
            channelArtworkURL = url
        }

        if inItem, name == "enclosure", let raw = attributeDict["url"],
           let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            itemAudioURL = url
            itemMimeType = attributeDict["type"]
        }

        // Some feeds expose audio only through media:content.
        if inItem, name == "content", itemAudioURL == nil, let raw = attributeDict["url"],
           let url = URL(string: raw), let type = attributeDict["type"],
           type.hasPrefix("audio/") {
            itemAudioURL = url
            itemMimeType = type
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            switch name {
            case "title": itemTitle = text
            case "guid": itemGUID = text
            case "duration": itemDuration = parseDuration(text)
            case "pubDate": itemDate = parseDate(text)
            case "item":
                if let audioURL = itemAudioURL {
                    episodes.append(
                        PodcastEpisode(
                            title: itemTitle ?? "Episode",
                            guid: itemGUID,
                            duration: itemDuration,
                            publishedAt: itemDate,
                            audioURL: audioURL,
                            mimeType: itemMimeType
                        )
                    )
                }
                inItem = false
            default:
                break
            }
        } else {
            switch name {
            case "title" where channelTitle == nil: channelTitle = text
            case "author" where channelAuthor == nil: channelAuthor = text
            case "name" where channelAuthor == nil: channelAuthor = text
            case "url" where channelArtworkURL == nil:
                if let url = URL(string: text) { channelArtworkURL = url }
            default: break
            }
        }

        currentText = ""
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    private func parseDuration(_ value: String) -> Int? {
        guard !value.isEmpty else { return nil }
        if value.contains(":") {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            guard !parts.isEmpty else { return nil }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        return Int(value)
    }

    private func parseDate(_ value: String) -> Date? {
        for formatter in Self.dateFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
