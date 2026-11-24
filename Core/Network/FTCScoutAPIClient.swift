import CryptoKit
import Foundation

struct ScoutFeed<Value: Sendable>: Sendable {
    let value: Value
    let fetchedAt: Date
    let fallback: Bool

    var isStale: Bool { fallback || Date.now.timeIntervalSince(fetchedAt) > 300 }
}

enum ScoutAPIError: LocalizedError {
    case unavailable
    case response(Int)
    case badData

    var errorDescription: String? {
        switch self {
        case .unavailable: "FTCScout has no record for this request."
        case .response(429): "FTCScout is busy. Wait a moment before trying again."
        case .response(let status): "FTCScout returned HTTP \(status)."
        case .badData: "FTCScout returned incomplete or unreadable data."
        }
    }
}

actor FTCScoutAPIClient {
    static let shared = FTCScoutAPIClient()
    private static let rest = URL(string: "https://api.ftcscout.org/rest/v1")!
    private static let graph = URL(string: "https://api.ftcscout.org/graphql")!

    private let session: URLSession
    private let cacheDirectory: URL?
    private let cacheLifetime: TimeInterval = 180
    private var pending: [String: Task<Data, Error>] = [:]

    private struct Cached: Codable {
        let data: Data
        let fetchedAt: Date
    }

    private struct GraphQL<Value: Decodable>: Decodable {
        struct Problem: Decodable { let message: String }
        let data: Value?
        let errors: [Problem]?
    }

    private struct EventList: Decodable {
        struct Team: Decodable {
            struct Participation: Decodable { let event: FTCEvent? }
            let events: [Participation]
        }
        let teamByNumber: Team?
    }

    private struct RosterQuery: Decodable {
        let eventByCode: FTCRoster?
    }

    private struct EventQuery: Decodable {
        let eventByCode: FTCEvent?
    }

    init(session: URLSession = .shared, cacheDirectory: URL? = FileManager.default.urls(
         for: .cachesDirectory, in: .userDomainMask
    ).first?.appendingPathComponent("FTCScout-v1", isDirectory: true)) {
        self.session = session
        self.cacheDirectory = cacheDirectory
    }

    func events(team: Int, season: Int, refresh: Bool = false) async throws -> ScoutFeed<[FTCEvent]> {
        let request = try graphRequest(query: """
            query TeamEvents($team: Int!, $season: Int!) {
              teamByNumber(number: $team) {
                events(season: $season) {
                  event { season code name start end timezone location { venue city state } }
                }
              }
            }
            """, variables: ["team": team, "season": season])
        return try await load("events:\(team):\(season)", request, refresh: refresh) { data in
            let response = try JSONDecoder().decode(GraphQL<EventList>.self, from: data)
            guard response.errors?.isEmpty != false, let result = response.data else { throw ScoutAPIError.badData }
            guard let team = result.teamByNumber else { throw ScoutAPIError.unavailable }
            let events = team.events.compactMap(\.event)
            guard events.count == team.events.count else { throw ScoutAPIError.badData }
            var seen = Set<String>()
            return events.filter { $0.season == season && seen.insert($0.id).inserted }
                .sorted { ($0.firstDay ?? "", $0.code) < ($1.firstDay ?? "", $1.code) }
        }
    }

    func matches(event: FTCEvent, refresh: Bool = false) async throws -> ScoutFeed<[FTCMatch]> {
        let request = URLRequest(url: Self.restURL("events", String(event.season), event.code, "matches"))
        return try await load("matches:\(event.id)", request, refresh: refresh) { data in
            let matches = try JSONDecoder().decode([FTCMatch].self, from: data)
            guard matches.allSatisfy({ $0.eventSeason == event.season && $0.eventCode.caseInsensitiveCompare(event.code) == .orderedSame })
            else { throw ScoutAPIError.badData }
            var seen = Set<Int>()
            return matches.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
        }
    }

    func event(season: Int, code: String, refresh: Bool = false) async throws -> ScoutFeed<FTCEvent> {
        let canonicalCode = code.uppercased()
        let request = try graphRequest(query: """
            query EventDetails($season: Int!, $code: String!) {
              eventByCode(season: $season, code: $code) {
                season code name start end timezone location { venue city state }
              }
            }
            """, variables: ["season": season, "code": canonicalCode])
        return try await load("event:\(season):\(canonicalCode)", request, refresh: refresh) { data in
            let response = try JSONDecoder().decode(GraphQL<EventQuery>.self, from: data)
            guard response.errors?.isEmpty != false else { throw ScoutAPIError.badData }
            guard let event = response.data?.eventByCode else { throw ScoutAPIError.unavailable }
            guard event.season == season, event.code.uppercased() == canonicalCode else { throw ScoutAPIError.badData }
            return event
        }
    }

    func standings(event: FTCEvent, refresh: Bool = false) async throws -> ScoutFeed<[FTCParticipation]> {
        let request = URLRequest(url: Self.restURL("events", String(event.season), event.code, "teams"))
        return try await decoded("standings:\(event.id)", request, refresh: refresh)
    }

    func names(event: FTCEvent, refresh: Bool = false) async throws -> ScoutFeed<[Int: String]> {
        let request = try graphRequest(query: """
            query EventRoster($season: Int!, $code: String!) {
              eventByCode(season: $season, code: $code) { teams { team { number name } } }
            }
            """, variables: ["season": event.season, "code": event.code])
        return try await load("names:\(event.id)", request, refresh: refresh) { data in
            let response = try JSONDecoder().decode(GraphQL<RosterQuery>.self, from: data)
            guard let roster = response.data?.eventByCode else { throw ScoutAPIError.badData }
            return roster.teams.compactMap(\.team).reduce(into: [:]) { $0[$1.number] = $1.name }
        }
    }

    func team(number: Int) async throws -> ScoutFeed<FTCTeam> {
        try await decoded("team:\(number)", URLRequest(url: Self.restURL("teams", String(number))))
    }

    func teamEvents(number: Int, season: Int) async throws -> ScoutFeed<[FTCParticipation]> {
        try await decoded("history:\(number):\(season)",
                          URLRequest(url: Self.restURL("teams", String(number), "events", String(season))))
    }

    private func decoded<T: Decodable & Sendable>(_ key: String, _ request: URLRequest,
                                                  refresh: Bool = false) async throws -> ScoutFeed<T> {
        try await load(key, request, refresh: refresh) { data in
            try JSONDecoder().decode(T.self, from: data)
        }
    }

    private static func restURL(_ components: String...) -> URL {
        components.reduce(rest) { $0.appendingPathComponent($1) }
    }

    private func graphRequest(query: String, variables: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: Self.graph)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        return request
    }

    private func load<T: Sendable>(_ key: String, _ original: URLRequest, refresh: Bool,
                                   decode: (Data) throws -> T) async throws -> ScoutFeed<T> {
        let cached = readCache(key)
        if !refresh, let cached, Date.now.timeIntervalSince(cached.fetchedAt) < cacheLifetime,
           let value = try? decode(cached.data) {
            return ScoutFeed(value: value, fetchedAt: cached.fetchedAt, fallback: false)
        }

        var request = original
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task: Task<Data, Error>
        let createsRequest = pending[key] == nil
        if let existing = pending[key] {
            task = existing
        } else {
            let session = self.session
            task = Task { try await Self.fetch(request, session: session) }
            pending[key] = task
        }
        defer { if createsRequest { pending[key] = nil } }

        do {
            let bytes = try await task.value
            let value = try decode(bytes)
            let stamp = Date.now
            writeCache(Cached(data: bytes, fetchedAt: stamp), key: key)
            return ScoutFeed(value: value, fetchedAt: stamp, fallback: false)
        } catch {
            if let cached, let value = try? decode(cached.data) {
                return ScoutFeed(value: value, fetchedAt: cached.fetchedAt, fallback: true)
            }
            if error is DecodingError { throw ScoutAPIError.badData }
            throw error
        }
    }

    private static func fetch(_ request: URLRequest, session: URLSession) async throws -> Data {
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ScoutAPIError.badData }
                if (200..<300).contains(http.statusCode) { return data }
                if http.statusCode == 404 { throw ScoutAPIError.unavailable }
                let retryDelay = http.value(forHTTPHeaderField: "Retry-After")
                let delay = retryDelay.flatMap(Double.init) ?? 0.8
                if attempt == 0, (http.statusCode == 429 || (500...599).contains(http.statusCode)),
                   retryDelay == nil || Double(retryDelay ?? "") != nil, delay >= 0, delay <= 3 {
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw ScoutAPIError.response(http.statusCode)
            } catch let error as URLError where attempt == 0 &&
                [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                try await Task.sleep(for: .milliseconds(650))
            }
        }
        throw ScoutAPIError.badData
    }

    private func readCache(_ key: String) -> Cached? {
        guard let url = cacheURL(key), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Cached.self, from: data)
    }

    private func writeCache(_ item: Cached, key: String) {
        guard let url = cacheURL(key), let bytes = try? JSONEncoder().encode(item) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url, options: .atomic)
        } catch {
            // A full cache volume doesn't invalidate a successful network response.
        }
    }

    private func cacheURL(_ key: String) -> URL? {
        let file = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory?.appendingPathComponent(file + ".json")
    }
}
