import SwiftUI
import SwiftData

struct PitReportEditor: View {
    let event: FTCEvent
    let directory: TeamDirectory
    var previous: PitObservation?

    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var auth

    @State private var team = ""
    @State private var drivetrain = ""
    @State private var mechanisms = ""
    @State private var auto = ""
    @State private var starts = ""
    @State private var capabilities = ""
    @State private var dimensions = ""
    @State private var reliability = ""
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(event.name) {
                    TextField("FTC team number", text: $team)
                        .keyboardType(.numberPad)
                    if let number = Int(team.trimmed), let name = directory.names[number] {
                        Text(name).foregroundStyle(.secondary)
                    }
                }
                Section("Robot") {
                    TextField("Drivetrain", text: $drivetrain)
                    TextField("Major mechanisms", text: $mechanisms, axis: .vertical)
                    TextField("Dimensions and units", text: $dimensions)
                }
                Section(event.season == 2026 ? "BIOBUZZ Capabilities" : "Game Capabilities") {
                    TextField("Autonomous routine", text: $auto, axis: .vertical)
                    TextField("Compatible starting positions", text: $starts)
                    TextField(event.season == 2026 ? "Hive, garden and flower capabilities" : "Scoring and parking capabilities",
                              text: $capabilities, axis: .vertical)
                }
                Section("Reliability & Notes") {
                    TextField("Reliability concerns or none reported", text: $reliability, axis: .vertical)
                    TextField("Robot or driving observations", text: $notes, axis: .vertical)
                }
                FormSaveError(message: error)
            }
            .navigationTitle(previous == nil ? "Pit Observation" : "Pit Follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!(1...99999).contains(Int(team.trimmed) ?? 0) ||
                                  [drivetrain, mechanisms, auto, starts, capabilities, dimensions, reliability, notes]
                                    .allSatisfy { $0.trimmed.isEmpty })
                }
            }
            .onAppear {
                if let previous {
                    team = String(previous.team)
                    drivetrain = previous.drivetrain
                    mechanisms = previous.mechanisms
                    auto = previous.autonomous
                    starts = previous.startPositions
                    capabilities = previous.capabilities
                    dimensions = previous.dimensions
                    reliability = previous.reliability
                    notes = previous.notes
                }
            }
        }
    }

    private func save() {
        guard let author = auth.currentUser?.id, let number = Int(team.trimmed), (1...99999).contains(number) else { return }
        let entry = PitObservation(team: number, event: event, author: author, drivetrain: drivetrain.trimmed,
                                   mechanisms: mechanisms.trimmed, autonomous: auto.trimmed, startPositions: starts.trimmed,
                                   capabilities: capabilities.trimmed, dimensions: dimensions.trimmed,
                                   reliability: reliability.trimmed, notes: notes.trimmed)
        context.insert(entry)
        do {
            try saveWorkspace(context, in: shared)
            dismiss()
        } catch {
            context.rollback()
            self.error = "Couldn’t save this observation. Your edits are still here."
        }
    }
}

struct PitReportDetail: View {
    let report: PitObservation
    let event: FTCEvent?
    @Environment(CompetitionWorkspace.self) private var workspace
    @Environment(AuthenticationViewModel.self) private var auth
    @State private var followUp = false

    private var matchingEvent: FTCEvent? {
        if let event, event.code == report.eventCode, event.season == report.season { return event }
        return workspace.events?.value.first { $0.code == report.eventCode && $0.season == report.season }
    }

    var body: some View {
        List {
            Section("Team \(report.team) · \(report.eventCode)") {
                LabeledContent("Status", value: report.isComplete ? "Complete" : "Incomplete")
                LabeledContent("Recorded", value: report.created.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Observations") {
                ForEach([("Drivetrain", report.drivetrain), ("Major mechanisms", report.mechanisms),
                         ("Dimensions", report.dimensions), ("Autonomous", report.autonomous),
                         ("Starting positions", report.startPositions), ("Capabilities", report.capabilities),
                         ("Reliability", report.reliability), ("Notes", report.notes)], id: \.0) { title, value in
                    if !value.trimmed.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(title).font(.headline)
                            Text(value)
                        }
                    }
                }
            }
        }
        .navigationTitle("Pit Report")
        .toolbar {
            if report.author == auth.currentUser?.id, matchingEvent != nil {
                ToolbarItem(placement: .primaryAction) { Button("Follow-up") { followUp = true } }
            }
        }
        .sheet(isPresented: $followUp) {
            if let event = matchingEvent {
                PitReportEditor(event: event, directory: workspace.detail?.directory ?? TeamDirectory(), previous: report)
            }
        }
    }
}
