import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - SponsorBlockService
//
// Queries the SponsorBlock API (https://sponsor.ajay.app) to retrieve
// ad-skip segments for a given video, mirroring the Android
// SponsorBlockController functionality.

public actor SponsorBlockService {

    private let session: URLSession
    private let baseURL = "https://sponsor.ajay.app/api"

    public init() {
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
    }

    /// Test-only hook for injecting a stubbed `URLSession` (mirrors `InnerTubeAPI`'s
    /// equivalent init) — lets unit tests assert on the exact request `reportIncorrect`
    /// builds without hitting the live SponsorBlock API.
    init(session: URLSession) {
        self.session = session
    }

    /// Fetches sponsor segments for `videoId`.  Returns an empty array if the
    /// video has no segments or the request fails.
    public func fetchSegments(videoId: String, categories: Set<SponsorSegment.Category>) async -> [SponsorSegment] {
        guard !categories.isEmpty else { return [] }
        let cats = categories.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        let urlStr = "\(baseURL)/skipSegments?videoID=\(videoId)&categories=[\(cats)]"
        guard let url = URL(string: urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlStr)
        else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            return raw.compactMap { parse($0) }
        } catch {
            return []
        }
    }

    private func parse(_ dict: [String: Any]) -> SponsorSegment? {
        guard
            let segment = dict["segment"] as? [Double],
            segment.count == 2,
            let categoryStr = dict["category"] as? String,
            let category = SponsorSegment.Category(rawValue: categoryStr)
        else { return nil }
        return SponsorSegment(
            start: segment[0], end: segment[1], category: category, apiUUID: dict["UUID"] as? String)
    }

    /// Reports a segment as incorrect (#67) — SponsorBlock's downvote (`type=0`).
    /// `uuid` is the segment's `apiUUID` (its own identifier), not `SponsorSegment.id`.
    /// SponsorBlock requires a `userID` even for anonymous voting, to rate-limit abuse
    /// without any account — `SponsorBlockUserID.current` generates and persists one
    /// locally the first time it's needed.
    /// Returns `true` if the API accepted the vote (a 200 response).
    public func reportIncorrect(uuid: String) async -> Bool {
        var comps = URLComponents(string: "\(baseURL)/voteOnSponsorTime")
        comps?.queryItems = [
            URLQueryItem(name: "UUID", value: uuid),
            URLQueryItem(name: "userID", value: SponsorBlockUserID.current),
            URLQueryItem(name: "type", value: "0"),
        ]
        guard let url = comps?.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (_, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(statusCode)
        } catch {
            return false
        }
    }
}

// MARK: - SponsorBlockUserID
//
// SponsorBlock's vote/submit endpoints require a `userID` even for fully anonymous
// use — it's a random, locally-generated, non-account-linked string used only to
// rate-limit abuse. Generated once and persisted so repeat votes from this install
// are attributed consistently (matters for SponsorBlock's own reputation system,
// even though the app never surfaces an identity for it).
enum SponsorBlockUserID {
    private static let defaultsKey = "com.smarttube.sponsorBlockUserID"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: defaultsKey)
        return generated
    }
}

// MARK: - DeArrowService
//
// Queries the DeArrow API to retrieve community-provided titles and
// thumbnails, mirroring the Android DeArrowController functionality.

public actor DeArrowService {

    private let session: URLSession
    private let baseURL = "https://sponsor.ajay.app/api/branding"

    public init() {
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
    }

    init(session: URLSession) { self.session = session }

    public struct BrandingInfo: Sendable, Codable {
        public let title: String?
        public let thumbnailTimestamp: Double?
    }

    public func fetchBranding(videoId: String) async -> BrandingInfo {
        guard let url = URL(string: "\(baseURL)?videoID=\(videoId)") else {
            return BrandingInfo(title: nil, thumbnailTimestamp: nil)
        }
        do {
            let (data, _) = try await session.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let titles = json["titles"] as? [[String: Any]]
            let title = titles?.first(where: { ($0["votes"] as? Int ?? 0) >= 0 })?["title"] as? String
            let thumbs = json["thumbnails"] as? [[String: Any]]
            let ts = thumbs?.first(where: { ($0["votes"] as? Int ?? 0) >= 0 })?["timestamp"] as? Double
            return BrandingInfo(title: title, thumbnailTimestamp: ts)
        } catch {
            return BrandingInfo(title: nil, thumbnailTimestamp: nil)
        }
    }
}
