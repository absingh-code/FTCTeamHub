import SwiftUI
import SwiftData

struct WorkTabView: View {
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text("Tasks").tag(0)
                    Text("Notebook").tag(1)
                    Text("Ideas").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

                switch segment {
                case 0:
                    TasksListView()
                case 1:
                    NotebookListView()
                default:
                    IdeasListView()
                }
            }
            .background(DS.Color.background)
            .navigationTitle("Work")
        }
    }
}

// MARK: - Tasks

struct TasksListView: View {
    @Query(sort: \TaskItem.dateCreated, order: .reverse) private var tasks: [TaskItem]
    @State private var showingForm = false

    private let statuses = ["todo", "inProgress", "blocked", "done"]

    var body: some View {
        List {
            ForEach(statuses, id: \.self) { status in
                let filtered = tasks.filter { $0.status == status }
                if !filtered.isEmpty {
                    Section(header: Text(status.capitalized)) {
                        ForEach(filtered) { task in
                            NavigationLink(value: task) {
                                TaskRow(task: task)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Color.background)
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "No tasks",
                    systemImage: "checklist",
                    description: Text("Create a task to get started.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            TaskFormView()
        }
        .navigationDestination(for: TaskItem.self) { task in
            TaskDetailView(task: task)
        }
    }
}

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title)
                Picker("Status", selection: $task.status) {
                    Text("To do").tag("todo")
                    Text("In progress").tag("inProgress")
                    Text("Blocked").tag("blocked")
                    Text("Done").tag("done")
                }
                Picker("Priority", selection: $task.priority) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                DatePicker("Deadline", selection: Binding(
                    get: { task.deadline ?? Date() },
                    set: { task.deadline = $0 }
                ), displayedComponents: .date)
            }

            Section("Notes") {
                TextField("Notes", text: Binding(
                    get: { task.notes ?? "" },
                    set: { task.notes = $0 }
                ), axis: .vertical)
                .lineLimit(4...8)
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

struct TaskFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var authVM

    @State private var title = ""
    @State private var priority = "medium"
    @State private var deadline = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let item = TaskItem(
                            title: title,
                            assignedToID: authVM.currentUser?.id,
                            priority: priority,
                            deadline: deadline,
                            notes: notes.isEmpty ? nil : notes
                        )
                        context.insert(item)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Notebook

struct NotebookListView: View {
    @Query(sort: \NotebookEntry.timestamp, order: .reverse) private var entries: [NotebookEntry]
    @State private var search = ""
    @State private var showingEditor = false

    var filtered: [NotebookEntry] {
        if search.isEmpty { return entries }
        return entries.filter {
            $0.content.localizedCaseInsensitiveContains(search) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { entry in
                NavigationLink {
                    EntryDetailView(entry: entry)
                } label: {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(entry.content.prefix(120) + (entry.content.count > 120 ? "…" : ""))
                            .font(DS.Font.body)
                            .lineLimit(2)
                        HStack {
                            Text(entry.authorName)
                            Text("·")
                            Text(entry.timestamp, style: .date)
                        }
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.labelSecondary)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Color.background)
        .searchable(text: $search, prompt: "Search entries")
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No entries",
                    systemImage: "book",
                    description: Text("Add engineering notebook entries here.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            EntryEditorView()
        }
    }
}

struct EntryDetailView: View {
    let entry: NotebookEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Text(entry.content)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(entry.authorName)
                    Text("·")
                    Text(entry.timestamp, style: .date)
                }
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.labelSecondary)

                if !entry.tags.isEmpty {
                    FlowTags(tags: entry.tags)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .background(DS.Color.background)
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EntryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var authVM

    @State private var content = ""
    @State private var selectedTemplate: String?

    private let templates = [
        "Autonomous routing notes",
        "REV Control Hub config",
        "Sensor tuning log",
        "Hardware change log"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    ForEach(templates, id: \.self) { t in
                        Button(t) {
                            content = "## \(t)\n\n"
                            selectedTemplate = t
                        }
                    }
                }
                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("New entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let user = authVM.currentUser else { return }
                        let entry = NotebookEntry(
                            authorID: user.id,
                            authorName: user.name,
                            content: content,
                            tags: selectedTemplate.map { [$0] } ?? []
                        )
                        context.insert(entry)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Ideas

struct IdeasListView: View {
    @Query(sort: \Idea.dateCreated, order: .reverse) private var ideas: [Idea]
    @State private var showingForm = false

    var body: some View {
        List {
            ForEach(ideas) { idea in
                NavigationLink {
                    IdeaDetailView(idea: idea)
                } label: {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(idea.title)
                            .font(DS.Font.body)
                        Text(idea.body.prefix(80) + (idea.body.count > 80 ? "…" : ""))
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.labelSecondary)
                            .lineLimit(2)
                        Text("\(idea.upvotes) votes")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.labelTertiary)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Color.background)
        .overlay {
            if ideas.isEmpty {
                ContentUnavailableView(
                    "No ideas",
                    systemImage: "lightbulb",
                    description: Text("Propose mechanisms or strategy changes here.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingForm = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            IdeaFormView()
        }
    }
}

struct IdeaDetailView: View {
    @Bindable var idea: Idea
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section {
                Text(idea.title)
                    .font(DS.Font.headline)
                Text(idea.body)
                    .font(DS.Font.body)
            }
            Section {
                Button {
                    idea.upvotes += 1
                    try? context.save()
                } label: {
                    Label("Upvote (\(idea.upvotes))", systemImage: "arrow.up")
                }
            }
        }
        .navigationTitle("Idea")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IdeaFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var authVM

    @State private var title = ""
    @State private var bodyText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $bodyText, axis: .vertical)
                    .lineLimit(4...10)
            }
            .navigationTitle("New idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let user = authVM.currentUser else { return }
                        let idea = Idea(
                            title: title,
                            body: bodyText,
                            authorID: user.id
                        )
                        context.insert(idea)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// Simple tag flow
struct FlowTags: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(DS.Font.caption)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.raised, in: Capsule())
            }
        }
    }
}
