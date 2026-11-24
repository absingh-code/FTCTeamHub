import SwiftUI

struct EventParticipationView: View {
    let participation: FTCParticipation
    @State private var info: ScoutFeed<FTCEvent>?
    @State private var matches: ScoutFeed<[FTCMatch]>?
    @State private var names: ScoutFeed<[Int: String]>?
    @State private var standings: ScoutFeed<[FTCParticipation]>?
    @State private var eventError: String?
    @State private var sectionError: String?
    @State private var loading = false

    private var directory: TeamDirectory { TeamDirectory(names: names?.value ?? [:]) }

    var body: some View {
        List {
            if let event = info?.value {
                Section {
                    Text(event.name).font(DS.Font.title)
                    if let date = event.dateLabel { Label(date, systemImage: "calendar") }
                    if let venue = event.venueLabel { Label(venue, systemImage: "mappin") }
                    if let stats = participation.stats {
                        LabeledContent("Rank", value: stats.standingRank.map(String.init) ?? "Unavailable")
                        LabeledContent("Qualification matches", value: stats.qualMatchesPlayed.map(String.init) ?? "Unavailable")
                        LabeledContent("Estimated NP OPR", value: TeamProfileView.format(stats.opr?.totalPointsNp))
                    }
                }
                Section("Matches for #\(participation.teamNumber)") {
                    let teamMatches = matches?.value.filter { $0.teamNumbers.contains(participation.teamNumber) }
                    if let teamMatches, teamMatches.isEmpty {
                        Text("No matches available for this team.").foregroundStyle(.secondary)
                    }
                    ForEach(teamMatches ?? []) { match in
                        NavigationLink {
                            MatchDetailView(event: event, match: match, directory: directory)
                        } label: { MatchRow(match: match, zone: event.zone) }
                    }
                }
                if let rankings = standings?.value.filter({ $0.stats?.standingRank != nil }).sorted(by: {
                    ($0.stats?.standingRank ?? .max, $0.teamNumber) < ($1.stats?.standingRank ?? .max, $1.teamNumber)
                }), !rankings.isEmpty {
                    Section("Event Rankings") {
                        ForEach(rankings) { row in
                            NavigationLink {
                                TeamProfileView(number: row.teamNumber, event: event, directory: directory,
                                                stats: row.stats, matches: matches?.value ?? [])
                            } label: {
                                LabeledContent(directory.label(row.teamNumber), value: row.stats?.standingRank.map { "\($0)" } ?? "—")
                            }
                        }
                    }
                }
                Section {
                    let fetched = [info?.fetchedAt, matches?.fetchedAt, standings?.fetchedAt, names?.fetchedAt]
                        .compactMap { $0 }.min()
                    if let fetched {
                        LabeledContent("FTCScout data fetched", value: fetched.formatted(date: .abbreviated, time: .shortened))
                    }
                    if [info?.fallback, matches?.fallback, standings?.fallback, names?.fallback].contains(where: { $0 == true }) {
                        Label("Showing some previously downloaded data", systemImage: "clock.arrow.circlepath")
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Loading event") }
            if let error = eventError ?? sectionError {
                DataNotice(title: "Some event data is unavailable", detail: error, icon: "calendar.badge.exclamationmark", retry: {
                    Task { await load(refresh: true) }
                })
            }
        }
        .navigationTitle(info?.value.name ?? participation.eventCode)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(refresh: true) }
    }

    private func load(refresh: Bool = false) async {
        guard !loading else { return }
        loading = true
        eventError = nil
        sectionError = nil
        defer { loading = false }
        let api = FTCScoutAPIClient.shared
        do {
            let detail = try await api.event(season: participation.season, code: participation.eventCode, refresh: refresh)
            info = detail
            async let matchFeed = capture { try await api.matches(event: detail.value, refresh: refresh) }
            async let standingFeed = capture { try await api.standings(event: detail.value, refresh: refresh) }
            async let nameFeed = capture { try await api.names(event: detail.value, refresh: refresh) }
            let (matchResult, standingResult, nameResult) = await (matchFeed, standingFeed, nameFeed)
            switch matchResult {
            case .success(let feed): matches = feed
            case .failure: sectionError = "The match schedule couldn’t be loaded."
            }
            switch standingResult {
            case .success(let feed): standings = feed
            case .failure: sectionError = "The event rankings couldn’t be loaded."
            }
            switch nameResult {
            case .success(let feed): names = feed
            case .failure:
                if sectionError == nil { sectionError = "Team names are temporarily unavailable." }
            }
        } catch {
            eventError = error.localizedDescription
        }
    }

    private func capture<T: Sendable>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}
