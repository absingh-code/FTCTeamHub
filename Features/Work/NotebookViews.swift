import SwiftUI
import SwiftData

struct NotebookListView: View {
    @Query(sort: \NotebookEntry.timestamp, order: .reverse) private var entries: [NotebookEntry]
    @State private var search = ""
    @State private var showingEditor = false

    var body: some View {
        let shown = entries.filter { entry in
            search.trimmed.isEmpty || ([entry.content, entry.authorName, entry.hardwareConfigLinked ?? ""] + entry.tags)
                .contains { $0.localizedCaseInsensitiveContains(search.trimmed) }
        }
        List {
            Section("Engineering Notebook") {
                if shown.isEmpty {
                    Text(entries.isEmpty ? "Record a decision, test, meeting or team resource." : "No entries match your search.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { entry in
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(entry.tags.first ?? "Notebook entry").font(.headline)
                            Text(entry.content.prefix(120)).lineLimit(2)
                            Text("\(entry.authorName) · \(entry.timestamp.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search notes, categories, authors or links")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Notebook Entry", systemImage: "plus") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) { EntryEditorView() }
    }
}

private struct EntryDetailView: View {
    let entry: NotebookEntry

    var body: some View {
        let links = WorkspaceLinks.links(in: entry.content + "\n" + (entry.hardwareConfigLinked ?? ""))
        List {
            Section("Entry") {
                LabeledContent("Author", value: entry.authorName)
                LabeledContent("Date", value: entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                Text(entry.content).textSelection(.enabled)
            }
            if !links.isEmpty {
                Section("Resources") {
                    ForEach(links, id: \.self) { url in
                        Link(url.host ?? url.absoluteString, destination: url)
                    }
                }
            }
        }
        .navigationTitle(entry.tags.first ?? "Notebook Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EntryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var auth
    @State private var content = ""
    @State private var selected = "Engineering decision"
    @State private var link = ""
    @State private var error: String?

    private let templates: [(title: String, fields: [String])] = [
        ("Engineering decision", ["Subsystem", "Decision", "Reason", "Next action"]),
        ("Testing log", ["Subsystem", "What we tested", "Configuration", "Result", "Follow-up"]),
        ("Meeting notes", ["Decisions", "Open questions", "Action items"]),
        ("Match retrospective", ["Event and match", "What worked", "What failed", "Next practice goal"]),
        ("Team resource", ["Resource", "What it’s for", "Owner or team area"]),
        ("Outreach activity", ["Activity and date", "Team participation", "Outcome", "Supporting evidence"])
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Entry type", selection: $selected) {
                        ForEach(templates, id: \.title) { Text($0.title).tag($0.title) }
                    }
                    Button("Insert Template") {
                        guard let template = templates.first(where: { $0.title == selected }) else { return }
                        content += (content.isEmpty ? "" : "\n\n") + template.fields.map { "\($0): " }.joined(separator: "\n\n")
                    }
                }
                Section("Notes") {
                    TextEditor(text: $content)
                        .frame(minHeight: 190)
                        .accessibilityLabel("Entry notes")
                }
                Section("Resource Link") {
                    TextField("CAD, code, document or evidence URL", text: $link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !validLink { Text("Enter a full HTTPS URL.").font(.footnote).foregroundStyle(.secondary) }
                }
                FormSaveError(message: error)
            }
            .navigationTitle("New Notebook Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled((content.trimmed.isEmpty && link.trimmed.isEmpty) || !validLink)
                }
            }
        }
    }

    private var validLink: Bool {
        link.trimmed.isEmpty || WorkspaceLinks.links(in: link.trimmed).first?.absoluteString == link.trimmed
    }

    private func save() {
        guard let user = auth.currentUser else { return }
        context.insert(NotebookEntry(authorID: user.id, authorName: user.name, content: content.trimmed,
                                     tags: [selected], hardwareConfigLinked: link.trimmed.isEmpty ? nil : link.trimmed))
        do {
            try saveWorkspace(context, in: shared)
            dismiss()
        } catch {
            context.rollback()
            self.error = "Couldn’t save the notebook entry. Your edits are still here."
        }
    }
}
