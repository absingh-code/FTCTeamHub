import SwiftUI
import SwiftData

struct MatchReportStart: View {
    let target: ScoutTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var auth
    @State private var report: MatchObservation?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    MatchReportContent(report: report)
                } else if let error {
                    ContentUnavailableView {
                        Label("Report unavailable", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry", action: open)
                    }
                } else {
                    ProgressView("Opening report")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { if report == nil { open() } }
        }
    }

    private func open() {
        guard let author = auth.currentUser?.id else { return }
        let identity = target.match.key.entryID(team: target.team, author: author)
        do {
            if let found = try context.fetch(FetchDescriptor<MatchObservation>(
                predicate: #Predicate { $0.identity == identity }
            )).first {
                report = found
                return
            }
            let draft = MatchObservation(target: target, author: author)
            context.insert(draft)
            try context.save()
            report = draft
        } catch {
            context.rollback()
            self.error = "The local report couldn’t be opened or saved."
        }
    }
}

struct MatchReportContent: View {
    let report: MatchObservation

    @Environment(\.modelContext) private var context
    @Environment(AuthenticationViewModel.self) private var auth
    @State private var reopen = false
    @State private var error: String?

    var body: some View {
        if report.submittedAt == nil, report.author == auth.currentUser?.id {
            MatchReportEditor(report: report)
        } else {
            MatchReportSummary(report: report)
                .toolbar {
                    if report.author == auth.currentUser?.id {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Correct") { reopen = true }
                        }
                    }
                }
                .confirmationDialog("Reopen this report as a draft?", isPresented: $reopen, titleVisibility: .visible) {
                    Button("Reopen as Draft") {
                        report.submittedAt = nil
                        do { try context.save() }
                        catch {
                            context.rollback()
                            self.error = "Couldn’t reopen the report. Try again."
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The report returns to Draft status until you submit the correction.")
                }
                .alert("Couldn’t reopen", isPresented: Binding(
                    get: { error != nil }, set: { if !$0 { error = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }
}

private struct MatchReportEditor: View {
    @Bindable var report: MatchObservation
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var saveError: String?
    @State private var review = false

    private var revision: [String] {
        [report.autoLeave, report.autoPark, report.finalPark, report.stopped,
         report.autoNotes, report.teleopNotes, report.reliabilityNotes, report.notes] +
        [report.autoHiveTips, report.teleopHiveTips, report.gardenPieces, report.flowerPlacements]
            .map { $0.map { String($0) } ?? "" }
    }

    var body: some View {
        Form {
            Section {
                ReportHeading(report: report)
                if let saveError {
                    FormSaveError(message: saveError)
                    Button("Retry Saving", action: saveDraft)
                } else {
                    Label("Draft saved on this device", systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if report.schemaVersion == 1 {
                Section("Autonomous") {
                    ObservationPicker(label: "Robot left starting area", value: $report.autoLeave)
                    ObservationPicker(label: "Robot parked in loading zone", value: $report.autoPark)
                    ObservationCounter(label: "Hive tips observed", value: $report.autoHiveTips)
                    TextField("Autonomous notes", text: $report.autoNotes, axis: .vertical)
                }
                Section("TeleOp") {
                    ObservationCounter(label: "Hive tips observed", value: $report.teleopHiveTips)
                    ObservationCounter(label: "Pieces placed in garden", value: $report.gardenPieces)
                    ObservationCounter(label: "Pieces placed in flowers", value: $report.flowerPlacements)
                    TextField("Other TeleOp notes", text: $report.teleopNotes, axis: .vertical)
                }
                Section("End of TeleOp") {
                    ObservationPicker(label: "Robot parked in loading zone", value: $report.finalPark)
                }
            } else {
                Section("Autonomous") {
                    TextField("What did the robot do?", text: $report.autoNotes, axis: .vertical).lineLimit(2...5)
                }
                Section("TeleOp") {
                    TextField("Cycles, capabilities and final actions", text: $report.teleopNotes, axis: .vertical).lineLimit(2...5)
                }
            }
            Section("Reliability & Penalties") {
                ObservationPicker(label: "Robot stopped unexpectedly", value: $report.stopped)
                TextField("Breakdowns or observed penalties", text: $report.reliabilityNotes, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section("Other Observations") {
                TextField("Driver strategy or match notes", text: $report.notes, axis: .vertical).lineLimit(2...5)
            }
        }
        .navigationTitle("Match Draft")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Review") {
                    saveDraft()
                    if saveError == nil { review = true }
                }
                .disabled(!report.hasObservations)
            }
        }
        .onChange(of: revision) { _, _ in saveDraft() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveDraft() } }
        .interactiveDismissDisabled(saveError != nil)
        .navigationDestination(isPresented: $review) {
            ReviewMatchReport(report: report)
        }
    }

    private func saveDraft() {
        guard report.submittedAt == nil, context.hasChanges else { return }
        report.updated = .now
        do {
            try context.save()
            saveError = nil
        } catch {
            saveError = "Couldn’t save your draft. Keep this screen open and retry."
        }
    }
}

struct ObservationPicker: View {
    let label: String
    @Binding var value: String

    var body: some View {
        Picker(label, selection: $value) {
            ForEach(Seen.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
    }
}

private struct ObservationCounter: View {
    let label: String
    @Binding var value: Int?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label)
                Spacer()
                controls
            }
            VStack(alignment: .leading) {
                Text(label)
                controls
            }
        }
    }

    private var controls: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button {
                value = max((value ?? 0) - 1, 0)
            } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled((value ?? 0) == 0)
            .accessibilityLabel("Decrease \(label)")

            Menu {
                Button("Record Zero") { value = 0 }
                Button("Mark Unobserved") { value = nil }
            } label: {
                Text(value.map { String($0) } ?? "—")
                    .font(DS.Font.number)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(label)
            .accessibilityValue(value.map { String($0) } ?? "Unobserved")

            Button {
                value = min((value ?? 0) + 1, 999)
            } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(value == 999)
            .accessibilityLabel("Increase \(label)")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
