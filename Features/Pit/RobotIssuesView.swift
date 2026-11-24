import SwiftUI
import SwiftData

struct RobotIssuesView: View {
    @Query(sort: \RobotIssue.updated, order: .reverse) private var issues: [RobotIssue]
    @State private var add = false
    @State private var search = ""
    @State private var filter = "Open"

    var body: some View {
        let shown = issues.filter { issue in
            (search.trimmed.isEmpty || [issue.title, issue.subsystem, issue.detail, issue.resolution, issue.owner]
                .contains { $0.localizedCaseInsensitiveContains(search.trimmed) }) &&
            (filter == "All" || (filter == "Open" && issue.isOpen) ||
             (filter == "Critical" && issue.isOpen && issue.severity == IssueSeverity.critical.rawValue) ||
             (filter == "Resolved" && !issue.isOpen))
        }
        List {
            Section {
                Picker("Show issues", selection: $filter) {
                    ForEach(["Open", "Critical", "Resolved", "All"], id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Issue Log") {
                if shown.isEmpty {
                    Text(issues.isEmpty ? "Log failures and repairs by subsystem." : "No issues match those filters.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { issue in
                    NavigationLink {
                        RobotIssueEditor(issue: issue)
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text(issue.title).font(.headline)
                            Text("\(issue.subsystem) · \(issue.status)")
                                .font(.footnote).foregroundStyle(.secondary)
                            if issue.severity == IssueSeverity.critical.rawValue {
                                StatusLabel(title: "Critical", icon: "exclamationmark.octagon", color: .red)
                            }
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
            if search.trimmed.isEmpty {
                let groups = Dictionary(grouping: issues, by: \.subsystem).filter { $0.value.count > 1 }
                if !groups.isEmpty {
                    Section("Recurring Subsystems") {
                        ForEach(groups.keys.sorted(), id: \.self) { name in
                            Button { search = name; filter = "All" } label: {
                                LabeledContent(name, value: "\(groups[name]?.count ?? 0) reports")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Robot Issues")
        .searchable(text: $search, prompt: "Search issues or subsystems")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Report an Issue", systemImage: "plus") { add = true }
            }
        }
        .sheet(isPresented: $add) { RobotIssueFormSheet() }
    }
}

struct RobotIssueFormSheet: View {
    var match: FTCMatch?

    var body: some View {
        NavigationStack { RobotIssueEditor(match: match) }
    }
}

struct RobotIssueEditor: View {
    var issue: RobotIssue?
    var match: FTCMatch?
    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var subsystem = RobotSubsystem.drivetrain
    @State private var severity = IssueSeverity.normal
    @State private var status = IssueStatus.open
    @State private var owner = ""
    @State private var resolution = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Issue") {
                TextField("Title", text: $title)
                TextField("What happened?", text: $detail, axis: .vertical).lineLimit(3...7)
                Picker("Subsystem", selection: $subsystem) {
                    ForEach(RobotSubsystem.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Severity", selection: $severity) {
                    ForEach(IssueSeverity.allCases) { Text($0.rawValue).tag($0) }
                }
                if let shared {
                    Picker("Owner", selection: $owner) {
                        Text("Unassigned").tag("")
                        ForEach(shared.members.filter { $0.role != "viewer" }) { member in
                            Text(member.name).tag(member.id)
                        }
                        if !owner.isEmpty && !shared.members.contains(where: { $0.id == owner && $0.role != "viewer" }) {
                            Text("Previous owner").tag(owner)
                        }
                    }
                } else {
                    TextField("Owner", text: $owner)
                }
                if let label = match?.label ?? issue?.matchLabel {
                    LabeledContent("Related match", value: label)
                }
            }
            Section("Resolution") {
                Picker("Status", selection: $status) {
                    ForEach(IssueStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("What fixed it?", text: $resolution, axis: .vertical).lineLimit(2...6)
                if status == .resolved && resolution.trimmed.isEmpty {
                    Text("Add a resolution note to mark this issue resolved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let issue {
                Section("History") {
                    LabeledContent("Reported", value: issue.created.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Last updated", value: issue.updated.formatted(date: .abbreviated, time: .shortened))
                }
            }
            FormSaveError(message: error)
        }
        .navigationTitle(issue == nil ? "New Robot Issue" : "Robot Issue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if issue == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(title.trimmed.isEmpty || (status == .resolved && resolution.trimmed.isEmpty) || shared?.team.canEdit == false)
            }
        }
        .onAppear {
            if let issue {
                title = issue.title
                detail = issue.detail
                subsystem = RobotSubsystem(rawValue: issue.subsystem) ?? .other
                severity = IssueSeverity(rawValue: issue.severity) ?? .normal
                status = IssueStatus(rawValue: issue.status) ?? .open
                owner = issue.owner
                resolution = issue.resolution
            } else if let shared {
                owner = shared.uid
            }
        }
    }

    private func save() {
        guard !title.trimmed.isEmpty, status != .resolved || !resolution.trimmed.isEmpty else { return }
        if let issue {
            issue.title = title.trimmed
            issue.detail = detail.trimmed
            issue.subsystem = subsystem.rawValue
            issue.severity = severity.rawValue
            issue.status = status.rawValue
            issue.owner = owner.trimmed
            issue.resolution = resolution.trimmed
            issue.updated = .now
        } else {
            context.insert(RobotIssue(title: title.trimmed, detail: detail.trimmed, subsystem: subsystem,
                                      severity: severity, status: status, owner: owner.trimmed,
                                      match: match, resolution: resolution.trimmed))
        }
        do {
            try saveWorkspace(context, in: shared)
            dismiss()
        } catch {
            context.rollback()
            self.error = "Couldn’t save this issue. Your edits are still here."
        }
    }
}
