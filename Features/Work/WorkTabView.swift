import SwiftUI
import SwiftData

struct WorkTabView: View {
    @State private var section = WorkSection.tasks

    enum WorkSection: String, CaseIterable {
        case tasks = "Tasks"
        case notebook = "Notebook"
        case ideas = "Ideas"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Work section", selection: $section) {
                    ForEach(WorkSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

                switch section {
                case .tasks: TasksListView()
                case .notebook: NotebookListView()
                case .ideas: IdeasListView()
                }
            }
            .background(DS.Color.background)
            .navigationTitle("Work")
        }
    }
}

private struct TasksListView: View {
    @Environment(AuthenticationViewModel.self) private var auth
    @Query(sort: \TaskItem.dateCreated, order: .reverse) private var tasks: [TaskItem]
    @State private var adding = false
    @State private var search = ""
    @State private var filter = "Open"

    private var filtered: [TaskItem] {
        tasks.filter { task in
            let term = search.trimmed
            guard term.isEmpty || ([task.title, task.notes ?? ""] + task.tags).contains(where: {
                $0.localizedCaseInsensitiveContains(term)
            }) else { return false }
            switch filter {
            case "My tasks": return task.assignedToID == auth.currentUser?.id && task.status != "done"
            case "Overdue": return task.status != "done" && task.deadline.map { $0 < Calendar.current.startOfDay(for: .now) } == true
            case "Completed": return task.status == "done"
            case "Open": return task.status != "done"
            default: return true
            }
        }.sorted {
            ($0.deadline ?? .distantFuture, $0.dateCreated) < ($1.deadline ?? .distantFuture, $1.dateCreated)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show tasks", selection: $filter) {
                    ForEach(["Open", "My tasks", "Overdue", "Completed", "All"], id: \.self) { Text($0).tag($0) }
                }
            }
            if filtered.isEmpty {
                Section {
                    Text(tasks.isEmpty ? "Add a task to track who’s doing it and when it’s due." : "No tasks match those filters.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(TaskEditor.statuses, id: \.rawValue) { status in
                let rows = filtered.filter {
                    return $0.status == status.rawValue ||
                        (status.rawValue == "todo" && !TaskEditor.statuses.map(\.rawValue).contains($0.status))
                }
                if !rows.isEmpty {
                    Section(status.name) {
                        ForEach(rows) { task in
                            NavigationLink { TaskEditor(task: task) } label: { TaskRow(task: task) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Search title, category or notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Task", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { TaskEditor() } }
    }
}

struct TaskEditor: View {
    var task: TaskItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var auth
    @Query(sort: \AppUser.name) private var members: [AppUser]
    @State private var title = ""
    @State private var assignee: String?
    @State private var status = "todo"
    @State private var priority = "medium"
    @State private var hasDeadline = false
    @State private var date = Date.now
    @State private var category = ""
    @State private var notes = ""
    @State private var error: String?

    static let statuses = [
        (rawValue: "todo", name: "To Do"), (rawValue: "inProgress", name: "In Progress"),
        (rawValue: "blocked", name: "Blocked"), (rawValue: "done", name: "Done")
    ]

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $title)
                Picker("Status", selection: $status) {
                    ForEach(Self.statuses, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                Picker("Priority", selection: $priority) {
                    ForEach(["low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Picker("Assignee", selection: $assignee) {
                    Text("Unassigned").tag(nil as String?)
                    if let user = auth.currentUser { Text("Me").tag(Optional(user.id)) }
                    ForEach(members.filter { $0.id != auth.currentUser?.id }) { member in
                        Text(member.name).tag(Optional(member.id))
                    }
                    if let assignee, assignee != auth.currentUser?.id, !members.contains(where: { $0.id == assignee }) {
                        Text("Previous assignee").tag(Optional(assignee))
                    }
                }
                TextField("Subsystem or category", text: $category)
                Toggle("Due date", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Due", selection: $date, displayedComponents: .date)
                }
            }
            Section("Notes & Links") {
                TextField("Details or relevant links", text: $notes, axis: .vertical).lineLimit(3...7)
                ForEach(WorkspaceLinks.links(in: notes), id: \.self) { url in
                    Link(url.host ?? url.absoluteString, destination: url)
                }
            }
            FormSaveError(message: error)
        }
        .navigationTitle(task == nil ? "New Task" : "Task Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if task == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(title.trimmed.isEmpty)
            }
        }
        .onAppear {
            if let task {
                title = task.title
                assignee = task.assignedToID
                status = Self.statuses.contains { $0.rawValue == task.status } ? task.status : "todo"
                priority = ["low", "medium", "high"].contains(task.priority) ? task.priority : "medium"
                hasDeadline = task.deadline != nil
                date = task.deadline ?? .now
                category = task.tags.joined(separator: ", ")
                notes = task.notes ?? ""
            }
        }
    }

    private func save() {
        let item = task ?? TaskItem(title: title.trimmed)
        if task == nil { context.insert(item) }
        item.title = title.trimmed
        item.status = status
        item.priority = priority
        item.assignedToID = assignee
        item.deadline = hasDeadline ? date : nil
        item.tags = category.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        item.notes = notes.trimmed.isEmpty ? nil : notes.trimmed
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            self.error = "Couldn’t save this task. Your edits are still here."
        }
    }
}

enum WorkspaceLinks {
    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<URL>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url).filter { $0.scheme == "https" && seen.insert($0).inserted }
    }
}
