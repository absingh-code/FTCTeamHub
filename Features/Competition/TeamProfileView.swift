import SwiftUI
import SwiftData

struct TeamProfileView: View {
    let number: Int
    let event: FTCEvent
    let directory: TeamDirectory
    let stats: FTCParticipation.Stats?
    let matches: [FTCMatch]
    private let useLiveProvider: Bool

    @State private var team: ScoutFeed<FTCTeam>?
    @State private var appearances: ScoutFeed<[FTCParticipation]>?
    @State private var profileError: String?
    @State private var historyError: String?
    @State private var loading = false
    @Query private var observations: [MatchObservation]
    @Query private var pits: [PitObservation]

    init(number: Int, event: FTCEvent, directory: TeamDirectory, stats: FTCParticipation.Stats?, matches: [FTCMatch],
         useLiveProvider: Bool = true) {
        self.number = number
        self.event = event
        self.directory = directory
        self.stats = stats
        self.matches = matches
        self.useLiveProvider = useLiveProvider
        let season = event.season
        let code = event.code
        _observations = Query(filter: #Predicate { $0.team == number && $0.season == season && $0.eventCode == code },
                              sort: \.updated, order: .reverse)
        _pits = Query(filter: #Predicate { $0.team == number && $0.season == season && $0.eventCode == code },
                      sort: \.created, order: .reverse)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("#\(String(number))").font(.subheadline.monospacedDigit()).foregroundStyle(DS.Color.accent)
                    Text(team?.value.name ?? directory.names[number] ?? "Team \(number)").font(DS.Font.display)
                    if let location = team?.value.location, !location.isEmpty {
                        Label(location, systemImage: "mappin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(event.name).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, DS.Spacing.sm)
                if loading && team == nil { ProgressView("Loading team profile") }
                if let profileError {
                    DataNotice(title: "Profile details unavailable", detail: profileError, icon: "wifi.exclamationmark")
                }
            }
            Section {
                LabeledContent("Rank", value: stats?.standingRank.map { String($0) } ?? "Unavailable")
                LabeledContent("Qualification matches", value: stats?.qualMatchesPlayed.map { String($0) } ?? "Unavailable")
                if let w = stats?.wins, let l = stats?.losses, let t = stats?.ties {
                    LabeledContent("Wins–losses–ties", value: "\(w)–\(l)–\(t)")
                }
                LabeledContent("Estimated NP OPR", value: Self.format(stats?.opr?.totalPointsNp))
            } header: {
                Text("Event Performance")
            } footer: {
                Text("FTCScout estimates non-penalty offensive contribution from alliance scores. An estimate from a few matches can change quickly.")
            }
            Section("Match History · This Event") {
                let teamMatches = matches.filter { $0.teamNumbers.contains(number) }
                if teamMatches.isEmpty {
                    Text("No listed matches at this event.").foregroundStyle(.secondary)
                }
                ForEach(teamMatches) { match in
                    NavigationLink {
                        MatchDetailView(event: event, match: match, directory: directory)
                    } label: { MatchRow(match: match, zone: event.zone) }
                }
            }
            Section("Event Participation · \(String(event.season))") {
                if let historyError {
                    DataNotice(title: "Season history unavailable", detail: historyError, icon: "calendar.badge.exclamationmark")
                }
                if let appearances {
                    if appearances.value.isEmpty { Text("No season events listed.").foregroundStyle(.secondary) }
                    ForEach(appearances.value.sorted { $0.eventCode < $1.eventCode }) { participation in
                        NavigationLink {
                            EventParticipationView(participation: participation)
                        } label: {
                            LabeledContent(participation.eventCode,
                                           value: participation.stats?.standingRank.map { "Rank \($0)" } ?? "Rank unavailable")
                        }
                    }
                }
            }
            Section("Team Scouting") {
                let reports = observations.filter { $0.submittedAt != nil }
                LabeledContent("Saved match reports", value: String(reports.count))
                if let pit = pits.first {
                    NavigationLink("Latest pit observation") { PitReportDetail(report: pit, event: event) }
                }
                ForEach(reports.prefix(5)) { report in
                    NavigationLink(report.matchLabel) { MatchReportSummary(report: report) }
                }
            }
            if let team {
                Section {
                    LabeledContent("FTCScout profile fetched", value: team.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                    if team.fallback || appearances?.fallback == true {
                        Text("Showing previously downloaded data")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Team \(String(number))")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    static func format(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(1))) ?? "Unavailable"
    }

    private func load() async {
        guard useLiveProvider, !loading else { return }
        loading = true
        defer { loading = false }
        let api = FTCScoutAPIClient.shared
        async let profile = api.team(number: number)
        async let history = api.teamEvents(number: number, season: event.season)
        do {
            team = try await profile
            profileError = nil
        } catch { profileError = error.localizedDescription }
        do {
            appearances = try await history
            historyError = nil
        } catch { historyError = error.localizedDescription }
    }
}

struct CompareTeamsView: View {
    let event: FTCEvent
    let numbers: [Int]
    let directory: TeamDirectory
    let standings: [Int: FTCParticipation.Stats]
    @State private var selected: Set<Int> = []
    @Query private var observations: [MatchObservation]
    @Query private var pits: [PitObservation]

    init(event: FTCEvent, numbers: [Int], directory: TeamDirectory, standings: [Int: FTCParticipation.Stats]) {
        self.event = event
        self.numbers = numbers
        self.directory = directory
        self.standings = standings
        let year = event.season
        let code = event.code
        _observations = Query(filter: #Predicate { $0.season == year && $0.eventCode == code && $0.submittedAt != nil })
        _pits = Query(filter: #Predicate { $0.season == year && $0.eventCode == code }, sort: \.created, order: .reverse)
    }

    var body: some View {
        List {
            if selected.count >= 2 {
                Section(event.name) {
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                            GridRow {
                                Text("Metric").font(.headline)
                                ForEach(selected.sorted(), id: \.self) { number in
                                    Text("#\(String(number))").font(.headline.monospacedDigit()).frame(minWidth: 78, alignment: .leading)
                                }
                            }
                            compareRow("Rank") { standings[$0]?.standingRank.map { String($0) } ?? "—" }
                            compareRow("Qual. matches") { standings[$0]?.qualMatchesPlayed.map { String($0) } ?? "—" }
                            compareRow("Est. NP OPR") { standings[$0]?.opr?.totalPointsNp.map { TeamProfileView.format($0) } ?? "—" }
                            compareRow("Reports") { number in String(observations.filter { $0.team == number }.count) }
                            compareRow("Stops observed") { number in
                                let known = observations.filter { $0.team == number && $0.stopped != Seen.unknown.rawValue }
                                return known.isEmpty ? "—" : "\(known.filter { $0.stopped == Seen.yes.rawValue }.count)/\(known.count)"
                            }
                            compareRow("Drivetrain") { number in
                                let value = pits.first { $0.team == number }?.drivetrain.trimmed ?? ""
                                return value.isEmpty ? "—" : value
                            }
                        }
                        .padding(.vertical, DS.Spacing.sm)
                    }
                    Text("OPR is FTCScout’s estimate. Reports, stops and drivetrain come from team observations. A dash means unavailable.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Select two or three teams") {
                ForEach(numbers, id: \.self) { number in
                    Toggle(directory.label(number), isOn: Binding(
                        get: { selected.contains(number) },
                        set: { value in
                            if value { selected.insert(number) } else { selected.remove(number) }
                        }
                    ))
                    .disabled(selected.count == 3 && !selected.contains(number))
                }
            }
        }
        .navigationTitle("Compare Teams")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func compareRow(_ name: String, value: @escaping (Int) -> String) -> some View {
        GridRow {
            Text(name).font(.subheadline)
            ForEach(selected.sorted(), id: \.self) { number in
                let text = value(number)
                Text(text).font(.subheadline.monospacedDigit())
                    .accessibilityLabel("#\(number), \(name), \(text == "—" ? "unavailable" : text)")
            }
        }
    }
}
