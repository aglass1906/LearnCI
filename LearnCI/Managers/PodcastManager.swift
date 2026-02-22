import Foundation
import SwiftData
import UIKit

// MARK: - iTunes Search Result

struct PodcastSearchResult: Identifiable, Hashable {
    let id: Int // iTunes trackId
    let name: String
    let artist: String
    let artworkUrl: String
    let feedUrl: String
    let genre: String
}

@Observable
class PodcastManager {
    var isLoading = false
    var errorMessage: String?
    var searchResults: [PodcastSearchResult] = []
    var isSearching = false

    // MARK: - Search via iTunes API

    func searchPodcasts(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=podcast&limit=25") else {
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = json?["results"] as? [[String: Any]] ?? []

            let parsed: [PodcastSearchResult] = results.compactMap { item in
                guard let trackId = item["trackId"] as? Int,
                      let name = item["trackName"] as? String,
                      let feedUrl = item["feedUrl"] as? String else { return nil }

                return PodcastSearchResult(
                    id: trackId,
                    name: name,
                    artist: item["artistName"] as? String ?? "",
                    artworkUrl: item["artworkUrl100"] as? String ?? "",
                    feedUrl: feedUrl,
                    genre: item["primaryGenreName"] as? String ?? ""
                )
            }

            await MainActor.run {
                self.searchResults = parsed
            }
        } catch {
            print("Podcast search failed: \(error)")
            await MainActor.run {
                self.searchResults = []
            }
        }
    }

    // MARK: - Subscribe

    func addPodcast(feedUrl: String, modelContext: ModelContext, userID: String? = nil) async {
        guard let url = URL(string: feedUrl) else {
            errorMessage = "Invalid URL"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parser = RSSParser(feedUrl: feedUrl)
            let result = parser.parse(data: data)

            guard let show = result.show else {
                errorMessage = result.error ?? "Failed to parse feed"
                isLoading = false
                return
            }

            await MainActor.run {
                show.userID = userID
                modelContext.insert(show)
                for episode in result.episodes {
                    episode.show = show
                    modelContext.insert(episode)
                }
                try? modelContext.save()
                isLoading = false
            }
        } catch {
            errorMessage = "Failed to fetch feed: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func refreshEpisodes(for show: PodcastShow, modelContext: ModelContext) async {
        guard let url = URL(string: show.feedUrl) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parser = RSSParser(feedUrl: show.feedUrl)
            let result = parser.parse(data: data)

            let existingUrls = Set(show.episodes.map { $0.audioUrl })

            await MainActor.run {
                // Update show metadata
                if let parsed = result.show {
                    show.title = parsed.title
                    show.author = parsed.author
                    show.showDescription = parsed.showDescription
                    show.artworkUrl = parsed.artworkUrl
                }

                for episode in result.episodes {
                    if !existingUrls.contains(episode.audioUrl) {
                        episode.show = show
                        modelContext.insert(episode)
                    }
                }
                try? modelContext.save()
            }
        } catch {
            print("Failed to refresh podcast: \(error)")
        }
    }
}

// MARK: - RSS XML Parser

private struct RSSParseResult {
    var show: PodcastShow?
    var episodes: [PodcastEpisode] = []
    var error: String?
}

private class RSSParser: NSObject, XMLParserDelegate {
    private let feedUrl: String
    private var result = RSSParseResult()

    // Parsing state
    private var currentElement = ""
    private var currentText = ""
    private var isInChannel = false
    private var isInItem = false

    // Channel-level fields
    private var channelTitle = ""
    private var channelAuthor = ""
    private var channelDescription = ""
    private var channelArtworkUrl: String?
    private var channelLanguage = ""

    // Item-level fields
    private var itemTitle = ""
    private var itemDescription = ""
    private var itemAudioUrl = ""
    private var itemPubDate = ""
    private var itemDuration = ""

    init(feedUrl: String) {
        self.feedUrl = feedUrl
    }

    func parse(data: Data) -> RSSParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "channel" {
            isInChannel = true
        } else if elementName == "item" {
            isInItem = true
            itemTitle = ""
            itemDescription = ""
            itemAudioUrl = ""
            itemPubDate = ""
            itemDuration = ""
        } else if elementName == "enclosure" && isInItem {
            if let url = attributes["url"],
               let type = attributes["type"], type.hasPrefix("audio") {
                itemAudioUrl = url
            }
        } else if elementName == "itunes:image" && !isInItem {
            if let href = attributes["href"] {
                channelArtworkUrl = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInItem {
            switch elementName {
            case "title": itemTitle = trimmed
            case "description": itemDescription = stripHTML(trimmed)
            case "pubDate": itemPubDate = trimmed
            case "itunes:duration": itemDuration = trimmed
            case "item":
                isInItem = false
                guard !itemAudioUrl.isEmpty else { return }
                let episode = PodcastEpisode(
                    title: itemTitle,
                    episodeDescription: itemDescription,
                    audioUrl: itemAudioUrl,
                    publishedDate: parseRSSDate(itemPubDate) ?? Date(),
                    duration: parseDuration(itemDuration)
                )
                result.episodes.append(episode)
            default: break
            }
        } else if isInChannel {
            switch elementName {
            case "title": channelTitle = trimmed
            case "itunes:author": channelAuthor = trimmed
            case "description": channelDescription = stripHTML(trimmed)
            case "language": channelLanguage = trimmed
            case "channel":
                isInChannel = false
                let show = PodcastShow(
                    title: channelTitle,
                    author: channelAuthor,
                    showDescription: channelDescription,
                    feedUrl: feedUrl,
                    artworkUrl: channelArtworkUrl,
                    language: languageFromCode(channelLanguage)
                )
                result.show = show
            default: break
            }
        }
    }

    // MARK: - Helpers

    private func parseRSSDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Standard RSS date format
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z",
                       "EEE, dd MMM yyyy HH:mm:ss zzz",
                       "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private func parseDuration(_ string: String) -> Double {
        // Could be "3600" (seconds), "01:00:00" (HH:MM:SS), or "60:00" (MM:SS)
        if let seconds = Double(string) { return seconds }

        let parts = string.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        default: return 0
        }
    }

    private func languageFromCode(_ code: String) -> Language {
        let prefix = String(code.prefix(2)).lowercased()
        switch prefix {
        case "es": return .spanish
        case "ja": return .japanese
        case "ko": return .korean
        case "fr": return .french
        case "vi": return .vietnamese
        case "en": return .english
        default: return .spanish
        }
    }

    private func stripHTML(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) else {
            // Fallback: simple regex strip
            return string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributed.string
    }
}
