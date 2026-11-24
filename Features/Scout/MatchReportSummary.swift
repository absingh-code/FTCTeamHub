import SwiftUI
import SwiftData

struct ReportHeading: View {
    let report: MatchObservation

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("#\(report.team) · \(report.matchLabel)").font(.headline)
            Text("\(report.eventCode) · \(report.season)–\(report.season + 1)")
                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MatchReportSummary: View {
    let report: MatchObservation

    var body: some View {
        List { ReportSummarySections(report: report) }
            .navigationTitle("Match Report")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReviewMatchReport: View {
    let report: MatchObservation

    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        List {
            ReportSummarySections(report: report)
            Section {
                Button(shared == nil ? "Save Report" : "Submit to Team", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(report.submittedAt != nil || !report.hasObservations || shared?.team.canEdit == false)
                FormSaveError(message: error)
            }
        }
        .navigationTitle("Review Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        guard report.submittedAt == nil, report.hasObservations else { return }
        report.submittedAt = .now
        report.updated = .now
        do {
            try saveWorkspace(context, in: shared)
            dismiss()
        } catch {
            context.rollback()
            self.error = "Couldn’t submit this report. Your draft is saved."
        }
    }
}

private struct ReportSummarySections: View {
    let report: MatchObservation
    @Environment(\.teamWorkspace) private var shared

    var body: some View {
        Section {
            ReportHeading(report: report)
            if let submitted = report.submittedAt {
                LabeledContent(shared?.reportDelivery(report.identity) ?? "Saved on device", value: submitted.formatted(date: .abbreviated, time: .shortened))
            } else {
                Label("Draft", systemImage: "pencil")
            }
        } footer: {
            Text("These are scout observations about one robot. The official result is listed with the match.")
        }
        if report.schemaVersion == 1 {
            Section("BIOBUZZ") {
                LabeledContent("Auto leave", value: report.autoLeave)
                LabeledContent("Auto park", value: report.autoPark)
                LabeledContent("Auto hive tips", value: count(report.autoHiveTips))
                LabeledContent("TeleOp hive tips", value: count(report.teleopHiveTips))
                LabeledContent("Garden pieces", value: count(report.gardenPieces))
                LabeledContent("Flower placements", value: count(report.flowerPlacements))
                LabeledContent("Final park", value: report.finalPark)
            }
        }
        Section("Notes") {
            LabeledContent("Unexpected stop", value: report.stopped)
            ForEach([("Autonomous", report.autoNotes), ("TeleOp", report.teleopNotes),
                     ("Reliability & penalties", report.reliabilityNotes), ("Other", report.notes)], id: \.0) { title, note in
                if !note.trimmed.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(title).font(.subheadline.weight(.medium))
                        Text(note)
                    }
                }
            }
        }
    }

    private func count(_ value: Int?) -> String {
        value.map { String($0) } ?? Seen.unknown.rawValue
    }
}
