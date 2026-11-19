import SwiftUI
import SwiftData

struct MatchDetailView: View {
    let event: FTCEvent
    let match: FTCMatch
    let directory: TeamDirectory

    @Environment(\.modelContext) private var context
    @Environment(AuthenticationViewModel.self) private var auth
    @Query private var assignments: [ScoutAssignment]
    @Query private var observations: [MatchObservation]
    @State private var target: ScoutTarget?
    @State private var showPlan = false
    @State private var showIssue = false
    @State private var saveError: String?

    init(event: FTCEvent, match: FTCMatch, directory: TeamDirectory) {
        self.event = event
        self.match = match
        self.directory = directory
        let key = match.key.id
        _assignments = Query(filter: #Predicate { $0.matchKey == key })
        _observations = Query(filter: #Predicate { $0.matchKey == key })
    }

    var body: some View {
        List {
            Section(event.name) {
                MatchRow(match: match, zone: event.zone)
                if match.teamNumbers.isEmpty {
                    Text("The provider hasn’t published alliance assignments.").foregroundStyle(.secondary)
                }
            }
            if !match.teamNumbers.isEmpty {
                Section {
                    ForEach(match.competitors.filter { $0.alliance.lowercased() != "solo" && $0.teamNumber > 0 },
                            id: \.teamNumber) { entry in
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text(directory.label(entry.teamNumber)).font(.headline)
                            Text(entry.alliance.capitalized + (entry.noShow == true ? " · No show" : "") +
                                 (entry.dq == true ? " · Disqualified" : "") +
                                 (entry.surrogate == true ? " · Surrogate" : ""))
                                .font(.footnote).foregroundStyle(.secondary)
                            HStack {
                                Button {
                                    target = ScoutTarget(match: match, team: entry.teamNumber)
                                } label: {
                                    Label(scoutLabel(entry.teamNumber), systemImage: "square.and.pencil")
                                }
                                .buttonStyle(.bordered)
                                if let user = auth.currentUser, entry.teamNumber != CompetitionWorkspace.teamNumber {
                                    let assigned = assignments.contains { $0.team == entry.teamNumber && $0.author == user.id }
                                    Button {
                                        toggleAssignment(team: entry.teamNumber, author: user.id)
                                    } label: {
                                        Label(assigned ? "Assigned" : "Assign to Me", systemImage: assigned ? "checkmark.circle.fill" : "person.badge.plus")
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityHint(assigned ? "Removes your assignment" : "Adds this team to your scouting assignments")
                                }
                            }
                            .controlSize(.large)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                    if match.competitors.contains(where: { $0.alliance.lowercased() == "solo" }) {
                        ForEach(match.teamNumbers, id: \.self) { number in
                            Button(directory.label(number)) { target = ScoutTarget(match: match, team: number) }
                        }
                    }
                    FormSaveError(message: saveError)
                } header: {
                    Text("Scouting & Assignments")
                } footer: {
                    Text("Assignments are saved in this workspace on this device.")
                }
            }
            Section("Match Preparation") {
                Button { showPlan = true } label: {
                    Label("Open Strategy Plan", systemImage: "list.bullet.clipboard")
                }
                NavigationLink {
                    ChecklistHub(match: match, event: event)
                } label: {
                    Label("Match Readiness Checks", systemImage: "checklist")
                }
                Button { showIssue = true } label: {
                    Label("Report Robot Issue", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .navigationTitle(match.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $target) { MatchReportStart(target: $0) }
        .sheet(isPresented: $showPlan) { MatchPlanEditor(event: event, match: match, directory: directory) }
        .sheet(isPresented: $showIssue) { RobotIssueFormSheet(match: match) }
    }

    private func scoutLabel(_ number: Int) -> String {
        guard let user = auth.currentUser,
              let row = observations.first(where: { $0.team == number && $0.author == user.id })
        else { return "Scout" }
        return row.submittedAt == nil ? "Resume Draft" : "View Report"
    }

    private func toggleAssignment(team: Int, author: String) {
        let id = match.key.entryID(team: team, author: author)
        if let saved = assignments.first(where: { $0.identity == id }) {
            context.delete(saved)
        } else {
            context.insert(ScoutAssignment(match: match, team: team, author: author))
        }
        do {
            try context.save()
            saveError = nil
        } catch {
            context.rollback()
            saveError = "Couldn’t update the assignment. Try again."
        }
    }
}

private struct MatchPlanEditor: View {
    let event: FTCEvent
    let match: FTCMatch
    let directory: TeamDirectory

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [MatchPlan]
    @Query private var pits: [PitObservation]
    @State private var auto = ""
    @State private var strategy = ""
    @State private var reminders = ""
    @State private var error: String?

    init(event: FTCEvent, match: FTCMatch, directory: TeamDirectory) {
        self.event = event
        self.match = match
        self.directory = directory
        let key = match.key.id
        let code = event.code
        let season = event.season
        _plans = Query(filter: #Predicate { $0.matchKey == key })
        _pits = Query(filter: #Predicate { $0.eventCode == code && $0.season == season },
                      sort: \.created, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(event.name) { MatchRow(match: match, zone: event.zone) }
                Section("Scouting Notes") {
                    ForEach(match.teamNumbers, id: \.self) { number in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(directory.label(number)).font(.headline)
                            if let pit = pits.first(where: { $0.team == number }) {
                                if !pit.autonomous.trimmed.isEmpty { Text("Auto · \(pit.autonomous)") }
                                if !pit.startPositions.trimmed.isEmpty { Text("Start · \(pit.startPositions)") }
                                if !pit.reliability.trimmed.isEmpty { Text("Reliability · \(pit.reliability)") }
                                if !pit.capabilities.trimmed.isEmpty { Text("Capabilities · \(pit.capabilities)") }
                            } else {
                                Text("No pit observations saved on this device.")
                            }
                        }
                        .font(.subheadline)
                    }
                }
                Section("Drive Team Plan") {
                    TextField("Autonomous and starting positions", text: $auto, axis: .vertical).lineLimit(2...5)
                    TextField("Alliance roles and match strategy", text: $strategy, axis: .vertical).lineLimit(3...7)
                    TextField("Drive team reminders", text: $reminders, axis: .vertical).lineLimit(2...5)
                }
                FormSaveError(message: error)
            }
            .navigationTitle("Strategy Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                if let plan = plans.first {
                    auto = plan.autonomous
                    strategy = plan.strategy
                    reminders = plan.reminders
                }
            }
        }
    }

    private func save() {
        let plan = plans.first ?? MatchPlan(matchKey: match.key.id, autonomous: "", strategy: "", reminders: "")
        if plans.isEmpty { context.insert(plan) }
        plan.autonomous = auto.trimmed
        plan.strategy = strategy.trimmed
        plan.reminders = reminders.trimmed
        plan.updated = .now
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            self.error = "Couldn’t save the strategy plan. Your edits are still here."
        }
    }
}
