import SwiftUI
import SwiftData

struct TodayTabView: View {
    let openTab: (MainTabView.Tab) -> Void

    @Environment(CompetitionWorkspace.self) private var competition
    @Environment(AuthenticationViewModel.self) private var auth
    @Query private var inventory: [InventoryItem]
    @Query private var tasks: [TaskItem]
    @Query(sort: \TeamEventRecord.date) private var localEvents: [TeamEventRecord]
    @Query(sort: \RobotIssue.updated, order: .reverse) private var issues: [RobotIssue]
    @Query(sort: \ChecklistRun.started, order: .reverse) private var checks: [ChecklistRun]
    @Query private var assignedScouting: [ScoutAssignment]
    @Query private var observations: [MatchObservation]
    @State private var addingIssue = false
    @State private var addingTask = false

    private var critical: [RobotIssue] {
        issues.filter { $0.isOpen && $0.severity == IssueSeverity.critical.rawValue }
    }

    private var dueTasks: [TaskItem] {
        tasks.filter {
            $0.status != "done" && ($0.assignedToID == nil || $0.assignedToID == auth.currentUser?.id)
        }.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TeamIdentity()
                        .padding(.vertical, DS.Spacing.sm)
                    if let event = competition.selected, event.isCurrent || competition.upcomingMatch != nil {
                        competitionSummary(event)
                    } else {
                        Button {
                            openTab(.competition)
                        } label: {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Label("Competition Schedule", systemImage: "calendar")
                                    .font(.headline)
                                Text(competition.selected?.name ?? "Choose an event to view matches and rankings.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, DS.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !critical.isEmpty {
                    Section("Critical Robot Issues") {
                        ForEach(critical.prefix(3)) { issue in
                            NavigationLink {
                                RobotIssueEditor(issue: issue)
                            } label: {
                                Label(issue.title, systemImage: "exclamationmark.octagon")
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                    }
                }
                Section("Due Tasks") {
                    if dueTasks.isEmpty {
                        Text("No open tasks assigned to you or left unassigned.").foregroundStyle(.secondary)
                    }
                    ForEach(dueTasks.prefix(4)) { task in
                        NavigationLink {
                            TaskEditor(task: task)
                        } label: { TaskRow(task: task) }
                    }
                    Button("See Team Tasks", systemImage: "arrow.right") { openTab(.work) }
                }
                Section("Quick Actions") {
                    Button("Scout a Match", systemImage: "binoculars") { openTab(.scout) }
                    Button("Report a Robot Issue", systemImage: "wrench.and.screwdriver") { addingIssue = true }
                    Button("Add a Task", systemImage: "plus") { addingTask = true }
                    NavigationLink {
                        ChecklistHub(match: competition.upcomingMatch, event: competition.selected)
                    } label: {
                        Label("Run a Readiness Check", systemImage: "checklist")
                    }
                }
                let upcoming = localEvents.filter { $0.date >= Calendar.current.startOfDay(for: .now) }
                if !upcoming.isEmpty {
                    Section("Local Team Events") {
                        ForEach(upcoming.prefix(4)) { event in
                            NavigationLink {
                                List {
                                    LabeledContent("Date", value: event.date.formatted(date: .abbreviated, time: .omitted))
                                    if !event.location.trimmed.isEmpty { LabeledContent("Location", value: event.location) }
                                    if !event.notes.trimmed.isEmpty { Text(event.notes) }
                                    ForEach(event.readinessChecklist.indices, id: \.self) { Text(event.readinessChecklist[$0]) }
                                }
                                .navigationTitle(event.name)
                            } label: {
                                LabeledContent(event.name, value: event.date.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    }
                }
                let low = inventory.filter { $0.quantity <= $0.lowStockThreshold }
                if !low.isEmpty {
                    Section("Inventory Alerts") {
                        ForEach(low.prefix(4)) { item in
                            NavigationLink {
                                InventoryEditor(item: item)
                            } label: {
                                LabeledContent(item.name, value: "\(item.quantity) left")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TeamTabView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $addingIssue) { RobotIssueFormSheet() }
            .sheet(isPresented: $addingTask) { NavigationStack { TaskEditor() } }
        }
    }

    @ViewBuilder
    private func competitionSummary(_ event: FTCEvent) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(event.isCurrent ? "AT COMPETITION" : "UP NEXT")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(DS.Color.accent)
                .accessibilityHidden(true)
            Text(event.name).font(DS.Font.title)
            if let location = event.venueLabel {
                Text(location).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.sm)

        if let match = competition.upcomingMatch, let detail = competition.detail {
            NavigationLink {
                MatchDetailView(event: event, match: match, directory: detail.directory)
            } label: {
                MatchRow(match: match, zone: event.zone)
            }
            let latest = checks.first { $0.matchKey == match.key.id && $0.templateKey == "pre-match" }
            NavigationLink {
                ChecklistHub(match: match, event: event)
            } label: {
                LabeledContent("Pre-match checklist", value: latest?.completed != nil ? "Complete" : latest == nil ? "Not started" : "In progress")
            }
        }
        let scouting = assignedScouting.filter { assignment in
            assignment.eventCode == event.code && assignment.author == auth.currentUser?.id &&
            !observations.contains { $0.identity == assignment.identity && $0.submittedAt != nil }
        }
        if !scouting.isEmpty {
            Button {
                openTab(.scout)
            } label: {
                LabeledContent("Scouting assignments", value: "\(scouting.count) open")
            }
        }
        if competition.detail?.hasCachedData == true {
            Label("Showing previously downloaded schedule", systemImage: "clock.arrow.circlepath")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(task.title).font(.headline)
            if !task.tags.isEmpty {
                Text(task.tags.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(task.priority.capitalized) priority")
                if let deadline = task.deadline {
                    Text(deadline, style: .date)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
