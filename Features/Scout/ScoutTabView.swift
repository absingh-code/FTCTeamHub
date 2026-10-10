import SwiftUI
import SwiftData

struct ScoutTabView: View {
    @Query(sort: \ScoutingRecord.timestamp, order: .reverse) private var records: [ScoutingRecord]
    @State private var showingEntry = false
    @State private var api = FTCScoutAPIClient()

    var body: some View {
        NavigationStack {
            List {
                Section("Local reports") {
                    if records.isEmpty {
                        Text("No scouting reports yet")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.labelSecondary)
                    } else {
                        ForEach(records) { rec in
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("Match \(rec.matchNumber) · Team \(rec.teamScouted)")
                                    .font(DS.Font.body)
                                    .foregroundStyle(DS.Color.labelPrimary)
                                Text("Auto \(rec.autoScore)  ·  Teleop \(rec.teleopScore)")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.labelSecondary)
                                if !rec.notes.isEmpty {
                                    Text(rec.notes)
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.labelTertiary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, DS.Spacing.xs)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .navigationTitle("Scout")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEntry = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        exportCSV()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(records.isEmpty)
                }
            }
            .sheet(isPresented: $showingEntry) {
                ScoutingEntryView()
            }
            .refreshable {
                await api.refreshEvents()
            }
            .overlay {
                if api.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Color.background.opacity(0.6))
                }
            }
            .alert("Could not load data", isPresented: Binding(
                get: { api.errorMessage != nil },
                set: { if !$0 { api.errorMessage = nil } }
            )) {
                Button("Retry") {
                    Task { await api.refreshEvents() }
                }
                Button("Dismiss", role: .cancel) {
                    api.errorMessage = nil
                }
            } message: {
                Text(api.errorMessage ?? "Unknown error")
            }
        }
    }

    private func exportCSV() {
        let csv = CSVExporter.export(records: records)
        // In production: present share sheet
        print(csv)
    }
}

struct ScoutingEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var authVM

    @State private var matchNumber = 1
    @State private var teamScouted = 0
    @State private var autoScore = 0
    @State private var teleopScore = 0
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    Stepper("Match number: \(matchNumber)", value: $matchNumber, in: 1...200)
                    TextField("Team number", value: $teamScouted, format: .number)
                        .keyboardType(.numberPad)
                }

                Section("Autonomous") {
                    LargeStepper(value: $autoScore, label: "Auto points", range: 0...100)
                }

                Section("Teleop") {
                    LargeStepper(value: $teleopScore, label: "Teleop points", range: 0...200)
                }

                Section("Notes") {
                    TextField("Observations", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let user = authVM.currentUser else { return }
                        let record = ScoutingRecord(
                            matchNumber: matchNumber,
                            teamScouted: teamScouted,
                            authorID: user.id,
                            autoScore: autoScore,
                            teleopScore: teleopScore,
                            notes: notes
                        )
                        context.insert(record)
                        try? context.save()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                    .disabled(teamScouted == 0)
                }
            }
        }
    }
}

struct LargeStepper: View {
    @Binding var value: Int
    let label: String
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(label)
                .font(DS.Font.body)
            Spacer()
            Button {
                if value > range.lowerBound {
                    value -= 1
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DS.Color.accent)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)

            Text("\(value)")
                .font(DS.Font.number)
                .frame(minWidth: 40)

            Button {
                if value < range.upperBound {
                    value += 1
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DS.Color.accent)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
        }
    }
}
