import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ScoutTabView: View {
    @Environment(CompetitionWorkspace.self) private var workspace
    @Environment(AuthenticationViewModel.self) private var auth
    @Query(sort: \MatchObservation.updated, order: .reverse) private var reports: [MatchObservation]
    @Query(sort: \ScoutingRecord.timestamp, order: .reverse) private var legacy: [ScoutingRecord]
    @Query(sort: \PitObservation.created, order: .reverse) private var pitReports: [PitObservation]
    @Query private var assignments: [ScoutAssignment]
    @State private var section = ScoutSection.matches
    @State private var search = ""
    @State private var savedOnly = false
    @State private var incompleteOnly = false
    @State private var showMatchPicker = false
    @State private var pitTeamPicker = false
    @State private var target: ScoutTarget?
    @State private var export: ScoutingCSV?
    @State private var exporting = false
    @State private var exportError: String?

    enum ScoutSection: String, CaseIterable {
        case matches = "Matches"
        case pit = "Pit Reports"
        case assignments = "Assignments"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Scouting view", selection: $section) {
                        ForEach(ScoutSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let event = workspace.selected {
                        Text(event.name).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                switch section {
                case .matches: matchList
                case .pit: pitList
                case .assignments: assignmentList
                }
            }
            .navigationTitle("Scout")
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Match, event, team or notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Match Report", systemImage: "square.and.pencil") { showMatchPicker = true }
                        Button("New Pit Observation", systemImage: "clipboard") { pitTeamPicker = true }
                            .disabled(workspace.selected == nil)
                        Button("Export Saved Matches as CSV", systemImage: "square.and.arrow.up") { prepareExport() }
                            .disabled(reports.allSatisfy { $0.submittedAt == nil } && legacy.isEmpty)
                    } label: { Label("Scouting Actions", systemImage: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showMatchPicker) {
                NavigationStack {
                    List {
                        if let event = workspace.selected, let detail = workspace.detail,
                           let matches = detail.matches?.value, !matches.isEmpty {
                            ForEach(matches) { match in
                                NavigationLink {
                                    MatchDetailView(event: event, match: match, directory: detail.directory)
                                } label: { MatchRow(match: match, zone: event.zone) }
                            }
                        } else {
                            DataNotice(title: "Schedule needed", detail: "Open Compete and download an event schedule before starting a match report.", icon: "calendar")
                        }
                    }
                    .navigationTitle("Select a Match")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showMatchPicker = false } }
                    }
                }
            }
            .sheet(isPresented: $pitTeamPicker) {
                if let event = workspace.selected {
                    PitReportEditor(event: event, directory: workspace.detail?.directory ?? TeamDirectory())
                }
            }
            .sheet(item: $target) { MatchReportStart(target: $0) }
            .fileExporter(isPresented: $exporting, document: export, contentType: .commaSeparatedText,
                          defaultFilename: "Wild-Circuits-scouting") { result in
                if case .failure = result { exportError = "The CSV couldn’t be exported. Try again." }
                export = nil
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil }, set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: { Text(exportError ?? "") }
        }
    }

    private var matchList: some View {
        let shown = reports.filter {
            (!savedOnly || $0.submittedAt != nil) &&
            matchesSearch(String($0.team), $0.matchLabel, $0.eventCode, $0.notes, $0.reliabilityNotes)
        }
        return Section {
            Toggle("Saved reports only", isOn: $savedOnly)
            Button("Scout a Match", systemImage: "plus") { showMatchPicker = true }
            if shown.isEmpty {
                Text(reports.isEmpty ? "Your draft will appear here after you choose a match and robot." : "No reports match those filters.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { report in
                NavigationLink {
                    MatchReportContent(report: report)
                } label: {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ReportHeading(report: report)
                        StatusLabel(title: report.submittedAt == nil ? "Draft" : "Saved on Device",
                                    icon: report.submittedAt == nil ? "pencil" : "checkmark.circle")
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
            ForEach(legacy.filter { matchesSearch(String($0.teamScouted), String($0.matchNumber), $0.eventCode ?? "", $0.notes) }) { report in
                NavigationLink("Match \(report.matchNumber) · #\(report.teamScouted) · Legacy") {
                    List {
                        Section("Original Report") {
                            LabeledContent("Auto points", value: String(report.autoScore))
                            LabeledContent("TeleOp points", value: String(report.teleopScore))
                            if let code = report.eventCode { LabeledContent("Event", value: code) }
                            if !report.notes.trimmed.isEmpty { Text(report.notes) }
                            Text(report.timestamp, style: .date)
                        }
                    }
                    .navigationTitle("Legacy Report")
                }
            }
        } header: { Text("Reports on This Device") }
    }

    private var pitList: some View {
        let shown = pitReports.filter {
            (!incompleteOnly || !$0.isComplete) &&
            matchesSearch(String($0.team), $0.eventCode, $0.drivetrain, $0.capabilities,
                          workspace.detail?.directory.names[$0.team] ?? "")
        }
        return Section {
            Button("Add Pit Observation", systemImage: "plus") { pitTeamPicker = true }
                .disabled(workspace.selected == nil)
            Toggle("Incomplete only", isOn: $incompleteOnly)
            if shown.isEmpty {
                Text(pitReports.isEmpty ? "Visit a team’s pit and record what their robot can do." : "No reports match those filters.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { report in
                NavigationLink {
                    PitReportDetail(report: report, event: workspace.selected)
                } label: {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(workspace.detail?.directory.label(report.team) ?? "Team \(report.team)")
                        Text("\(report.eventCode) · \(report.isComplete ? "Complete" : "Incomplete") · \(report.created.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } header: { Text("Pit History") }
    }

    private var assignmentList: some View {
        let current = assignments.filter { $0.author == auth.currentUser?.id }
        let matchLookup = Dictionary(uniqueKeysWithValues: (workspace.detail?.matches?.value ?? []).map { ($0.key.id, $0) })
        let shown = current.filter { matchesSearch(String($0.team), $0.matchLabel, $0.eventCode) }
            .sorted { ($0.scheduled ?? .distantFuture, $0.identity) < ($1.scheduled ?? .distantFuture, $1.identity) }
        return Group {
            Section("My Assignments") {
                if shown.isEmpty {
                    Text(current.isEmpty ? "Open a match and tap Assign to Me next to a robot to start your list." : "No assignments match your search.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { assignment in
                    let match = matchLookup[assignment.matchKey]
                    let report = reports.first { $0.identity == assignment.identity }
                    let status = report?.submittedAt != nil ? "Saved" : report != nil ? "Draft" :
                        match?.isPlayed == true ? "Report missing" : "Unstarted"
                    Button {
                        if let match { target = ScoutTarget(match: match, team: assignment.team) }
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("#\(assignment.team) · \(assignment.matchLabel)")
                            Text("\(assignment.eventCode) · \(status)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(match == nil)
                }
            }
            if let event = workspace.selected, let detail = workspace.detail {
                let own = detail.matches?.value.filter {
                    !$0.isPlayed && $0.teamNumbers.contains(CompetitionWorkspace.teamNumber)
                } ?? []
                let open = own.filter { match in
                    Set(match.teamNumbers.filter { $0 != CompetitionWorkspace.teamNumber })
                        .subtracting(current.filter { $0.matchKey == match.key.id }.map(\.team)).count > 0
                }
                Section("Upcoming Coverage Gaps") {
                    if own.isEmpty {
                        Text("No upcoming Wild Circuits matches are listed.").foregroundStyle(.secondary)
                    } else if open.isEmpty {
                        Text("All other robots in your upcoming matches are assigned on this device.").foregroundStyle(.secondary)
                    }
                    ForEach(open) { match in
                        NavigationLink {
                            MatchDetailView(event: event, match: match, directory: detail.directory)
                        } label: { MatchRow(match: match, zone: event.zone) }
                    }
                }
            }
        }
    }

    private func matchesSearch(_ items: String...) -> Bool {
        let term = search.trimmed
        return term.isEmpty || items.contains { $0.localizedCaseInsensitiveContains(term) }
    }

    private func prepareExport() {
        export = ScoutingCSV(text: CSVExporter.export(reports: reports.filter { $0.submittedAt != nil }, legacy: legacy))
        exporting = true
    }
}

private struct ScoutingCSV: FileDocument {
    static let readableContentTypes = [UTType.commaSeparatedText]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
