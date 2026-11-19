import SwiftUI

struct CompetitionTabView: View {
    @Environment(CompetitionWorkspace.self) private var workspace
    @State private var section = SectionKind.schedule
    @State private var search = ""
    @State private var oursOnly = false
    @State private var qualificationsOnly = false

    enum SectionKind: String, CaseIterable {
        case schedule = "Schedule"
        case teams = "Teams"
        case standings = "Rankings"
    }

    var body: some View {
        @Bindable var workspace = workspace
        NavigationStack {
            List {
                Section("Competition") {
                    if workspace.connection == .offline {
                        Label("Offline", systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary)
                    }
                    Picker("Season", selection: $workspace.season) {
                        ForEach(CompetitionWorkspace.seasons, id: \.self) { year in
                            Text(year == 2026 ? "2026–27 · BIOBUZZ" : "\(year)–\(year + 1)").tag(year)
                        }
                    }
                    if let events = workspace.events?.value, !events.isEmpty {
                        NavigationLink {
                            EventSelectionView(events: events)
                        } label: {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(workspace.selected?.name ?? "Choose Event")
                                if let event = workspace.selected {
                                    Text([event.dateLabel, event.venueLabel].compactMap { $0 }.joined(separator: " · "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else if workspace.loadingEvents {
                        ProgressView("Loading team events")
                    } else if let error = workspace.eventError {
                        DataNotice(title: "Events unavailable", detail: error, icon: "wifi.exclamationmark") {
                            Task { await workspace.loadEvents(refresh: true) }
                        }
                    } else if workspace.events != nil {
                        DataNotice(title: "No events for this season", detail: "Choose another season to see where Wild Circuits competed.", icon: "calendar")
                    }
                }

                if let event = workspace.selected {
                    Section {
                        Picker("Event view", selection: $section) {
                            ForEach(SectionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if let url = URL(string: "https://ftc-events.firstinspires.org/\(event.season)/\(event.code)") {
                            Link(destination: url) {
                                Label("Official FIRST Event", systemImage: "arrow.up.right.square")
                            }
                        }
                    }

                    if let detail = workspace.detail {
                        eventContent(event, detail: detail)
                        Section {
                            if let updated = detail.lastUpdated {
                                LabeledContent("FTCScout data", value: updated.formatted(date: .abbreviated, time: .shortened))
                            }
                            if detail.hasCachedData || workspace.events?.fallback == true {
                                Label("Showing previously downloaded data", systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                            }
                            if detail.hasError {
                                Button("Retry Event Data") { Task { await workspace.loadSelected(refresh: true) } }
                            }
                        }
                        .font(.footnote)
                    } else if workspace.loadingDetail {
                        Section { ProgressView("Loading event data") }
                    }
                }
            }
            .navigationTitle("Compete")
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: section == .schedule ? "Match or team number" : "Team name or number")
            .refreshable {
                await workspace.loadEvents(refresh: true)
                await workspace.loadSelected(refresh: true)
            }
        }
    }

    @ViewBuilder
    private func eventContent(_ event: FTCEvent, detail: CompetitionWorkspace.EventDetail) -> some View {
        switch section {
        case .schedule:
            Section {
                Toggle("Wild Circuits matches", isOn: $oursOnly)
                Toggle("Qualifications only", isOn: $qualificationsOnly)
            }
            Section("Matches") {
                if let error = detail.matchesError {
                    DataNotice(title: "Schedule refresh failed", detail: error, icon: "wifi.exclamationmark")
                }
                if let matches = detail.matches?.value {
                    let filtered = matches.filter { match in
                        (!oursOnly || match.teamNumbers.contains(CompetitionWorkspace.teamNumber)) &&
                        (!qualificationsOnly || match.isQualification) &&
                        (search.trimmed.isEmpty || match.label.localizedCaseInsensitiveContains(search.trimmed) ||
                         match.teamNumbers.contains { String($0).contains(search.trimmed) })
                    }
                    if filtered.isEmpty {
                        DataNotice(title: matches.isEmpty ? "Schedule unavailable" : "No matching matches",
                                   detail: matches.isEmpty ? "FTCScout has no matches for this event yet." : "Try changing your filters or search.",
                                   icon: "calendar")
                    }
                    ForEach(filtered) { match in
                        NavigationLink {
                            MatchDetailView(event: event, match: match, directory: detail.directory)
                        } label: {
                            MatchRow(match: match, zone: event.zone)
                        }
                    }
                }
            }
        case .teams, .standings:
            let numbers = Set((detail.standings?.value ?? []).map(\.teamNumber))
                .union(detail.names?.value.keys.map { $0 } ?? [])
                .union(detail.matches?.value.flatMap(\.teamNumbers) ?? [])
            let standings = (detail.standings?.value ?? []).reduce(into: [Int: FTCParticipation.Stats]()) {
                $0[$1.teamNumber] = $1.stats
            }
            let displayed = numbers.filter { detail.directory.label($0).localizedCaseInsensitiveContains(search.trimmed) || search.trimmed.isEmpty }
                .sorted { a, b in
                    if section == .teams { return a < b }
                    return (standings[a]?.rank ?? Int.max, a) < (standings[b]?.rank ?? Int.max, b)
                }
            if section == .teams && numbers.count >= 2 {
                Section {
                    NavigationLink {
                        CompareTeamsView(event: event, numbers: numbers.sorted(), directory: detail.directory, standings: standings)
                    } label: {
                        Label("Compare Teams", systemImage: "rectangle.split.2x1")
                    }
                }
            }
            Section(section.rawValue) {
                if let error = detail.standingsError {
                    DataNotice(title: "Rankings unavailable", detail: error, icon: "chart.bar.xaxis")
                } else if let error = detail.namesError {
                    DataNotice(title: "Team names unavailable", detail: error, icon: "person.2")
                }
                if displayed.isEmpty {
                    DataNotice(title: numbers.isEmpty ? "No teams available" : "No matching teams",
                               detail: numbers.isEmpty ? "Check back when a roster is available." : "Try another team name or number.",
                               icon: "person.2")
                }
                ForEach(displayed, id: \.self) { number in
                    NavigationLink {
                        TeamProfileView(number: number, event: event, directory: detail.directory,
                                        stats: standings[number], matches: detail.matches?.value ?? [])
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(detail.directory.label(number))
                            if section == .standings {
                                Text(standings[number]?.rank.map { "Rank \($0)" } ?? "Rank pending")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct EventSelectionView: View {
    let events: [FTCEvent]
    @Environment(CompetitionWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let term = search.trimmed
        let shown = events.filter {
            term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) || $0.code.localizedCaseInsensitiveContains(term)
        }
        List(shown) { event in
            Button {
                workspace.choose(event)
                dismiss()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(event.name).foregroundStyle(.primary)
                        if let label = event.dateLabel {
                            Text(label).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if event.id == workspace.selected?.id {
                        Image(systemName: "checkmark.circle.fill").accessibilityLabel("Selected")
                    }
                }
            }
        }
        .overlay { if shown.isEmpty { ContentUnavailableView.search(text: search) } }
        .navigationTitle("Team Events")
        .searchable(text: $search, prompt: "Event name or code")
    }
}

struct MatchRow: View {
    let match: FTCMatch
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top) {
                Text(match.label).font(.headline)
                Spacer()
                if match.isPlayed {
                    Text("Final").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            ForEach(["Red", "Blue"], id: \.self) { alliance in
                let entries = match.teams(on: alliance)
                if !entries.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(alliance).font(.caption.weight(.semibold))
                            .foregroundStyle(alliance == "Red" ? Color.red : Color.blue)
                        Text(entries.map { "#\($0.teamNumber)" }.joined(separator: " · "))
                            .font(.subheadline.monospacedDigit())
                        Spacer(minLength: 4)
                        if match.isPlayed {
                            let score = alliance == "Red" ? match.scores?.red?.totalPoints : match.scores?.blue?.totalPoints
                            Text(score.map { String($0) } ?? "—")
                                .font(DS.Font.number)
                                .accessibilityLabel(score.map { "\($0) points" } ?? "Score unavailable")
                        }
                    }
                }
            }
            MatchTime(match: match)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .environment(\.timeZone, zone)
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

struct MatchTime: View {
    let match: FTCMatch

    var body: some View {
        if let actual = match.actualDate {
            Text("Started \(actual, format: .dateTime.month(.abbreviated).day().hour().minute())")
        } else if !match.isPlayed, let scheduled = match.scheduledDate {
            Text("Scheduled \(scheduled, format: .dateTime.month(.abbreviated).day().hour().minute())")
        } else if match.isPlayed {
            Text("Actual start unavailable")
        } else {
            Text("Match time unavailable")
        }
    }
}
