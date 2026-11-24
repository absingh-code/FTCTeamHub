import Foundation

struct FTCEvent: Codable, Hashable, Identifiable, Sendable {
    struct Location: Codable, Hashable, Sendable {
        let venue: String?
        let city: String?
        let state: String?
    }

    let season: Int
    let code: String
    let name: String
    let start: String?
    let end: String?
    let timezone: String?
    let location: Location?
    let modifiedRules: Bool?

    var id: String { "\(season):\(code.uppercased())" }
    var venueLabel: String? {
        let parts = [location?.venue, location?.city, location?.state]
            .compactMap { $0 }.filter { !$0.trimmed.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var zone: TimeZone { timezone.flatMap(TimeZone.init(identifier:)) ?? .current }
    var firstDay: String? { start.map { String($0.prefix(10)) } }
    var lastDay: String? { end.map { String($0.prefix(10)) } }
    var dateLabel: String? {
        guard let firstDay, let first = displayDate(firstDay) else { return nil }
        guard let lastDay, lastDay != firstDay, let last = displayDate(lastDay) else { return first }
        return "\(first) – \(last)"
    }

    private func displayDate(_ date: String) -> String? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = zone
        parser.dateFormat = "yyyy-MM-dd"
        guard let value = parser.date(from: date) else { return nil }
        var style = Date.FormatStyle().month(.abbreviated).day()
        style.timeZone = zone
        return value.formatted(style)
    }

    var isCurrent: Bool {
        let local = DateFormatter()
        local.calendar = Calendar(identifier: .gregorian)
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = zone
        local.dateFormat = "yyyy-MM-dd"
        let today = local.string(from: .now)
        guard let firstDay, let lastDay else { return false }
        return firstDay <= today && today <= lastDay
    }
}

struct FTCTeam: Codable, Hashable, Identifiable, Sendable {
    let number: Int
    let name: String
    let city: String?
    let state: String?
    let country: String?
    let rookieYear: Int?
    let website: String?

    var id: Int { number }
    var location: String {
        [city, state, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct FTCMatch: Codable, Hashable, Identifiable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        let teamNumber: Int
        let alliance: String
        let station: String?
        let onField: Bool?
        let noShow: Bool?
        let dq: Bool?
        let surrogate: Bool?
    }

    struct Scores: Codable, Hashable, Sendable {
        struct Alliance: Codable, Hashable, Sendable {
            let totalPoints: Int?
            let totalPointsNp: Int?
            let autoPoints: Int?
            let dcPoints: Int?
        }
        let red: Alliance?
        let blue: Alliance?
    }

    let eventSeason: Int
    let eventCode: String
    let id: Int
    let hasBeenPlayed: Bool?
    let scheduledStartTime: String?
    let actualStartTime: String?
    let tournamentLevel: String?
    let series: Int?
    let scores: Scores?
    let teams: [Entry]?

    var key: MatchKey { MatchKey(season: eventSeason, eventCode: eventCode, providerID: id) }
    var isPlayed: Bool { hasBeenPlayed == true || (scores?.red?.totalPoints != nil && scores?.blue?.totalPoints != nil) }
    var isQualification: Bool { tournamentLevel?.lowercased().hasPrefix("qual") == true }
    var scheduledDate: Date? { Self.timestamp(scheduledStartTime) }
    var actualDate: Date? { Self.timestamp(actualStartTime) }
    var competitors: [Entry] {
        (teams ?? []).filter { $0.station?.lowercased() != "notonfield" }
    }
    var teamNumbers: [Int] { Array(Set(competitors.map(\.teamNumber))).sorted() }

    var label: String {
        let number = id % 1000
        if isQualification { return "Qualification \(number)" }
        switch tournamentLevel?.lowercased() {
        case "semis": return "Semifinal \(series ?? 0)–\(number)"
        case "finals": return "Final \(number)"
        case "doubleelim": return "Playoff \(series ?? 0)–\(number)"
        default: return "Match \(number)"
        }
    }

    func teams(on alliance: String) -> [Entry] {
        competitors.filter { $0.alliance.caseInsensitiveCompare(alliance) == .orderedSame }
            .sorted { ($0.station ?? "", $0.teamNumber) < ($1.station ?? "", $1.teamNumber) }
    }

    private static func timestamp(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

struct FTCParticipation: Codable, Hashable, Identifiable, Sendable {
    struct Stats: Codable, Hashable, Sendable {
        struct Estimate: Codable, Hashable, Sendable {
            let totalPoints: Double?
            let totalPointsNp: Double?
            let autoPoints: Double?
        }
        let rank: Int?
        let qualMatchesPlayed: Int?
        let wins: Int?
        let losses: Int?
        let ties: Int?
        let opr: Estimate?

        var standingRank: Int? { rank.flatMap { $0 > 0 ? $0 : nil } }
    }

    let season: Int
    let eventCode: String
    let teamNumber: Int
    let isRemote: Bool?
    let stats: Stats?

    var id: String { "\(season):\(eventCode):\(teamNumber)" }
}

struct FTCRoster: Codable, Sendable {
    struct Member: Codable, Sendable {
        let team: TeamName?
    }
    struct TeamName: Codable, Sendable {
        let number: Int
        let name: String
    }
    let teams: [Member]
}

struct TeamDirectory {
    var names: [Int: String] = [:]

    func label(_ number: Int) -> String {
        if let name = names[number], !name.trimmed.isEmpty { return "#\(number) · \(name)" }
        return "#\(number)"
    }
}
