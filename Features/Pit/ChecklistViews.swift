import SwiftUI
import SwiftData

struct ChecklistHub: View {
    var match: FTCMatch?
    var event: FTCEvent?
    @Environment(CompetitionWorkspace.self) private var workspace
    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Query(sort: \ChecklistRun.started, order: .reverse) private var runs: [ChecklistRun]
    @Query private var custom: [ChecklistTemplate]
    @State private var openRun: ChecklistRun?
    @State private var edit: ChecklistDefinition?
    @State private var error: String?

    private var eventID: String? { (event ?? workspace.selected)?.id }
    private var matchingRuns: [ChecklistRun] {
        if let match { return runs.filter { $0.matchKey == match.key.id } }
        return runs
    }

    var body: some View {
        List {
            Section {
                ForEach(ChecklistDefinition.defaults) { item in
                    let saved = custom.first { $0.key == item.id }
                    let template = ChecklistDefinition(id: item.id, title: saved?.title ?? item.title, items: saved?.items ?? item.items)
                    Button {
                        open(template)
                    } label: {
                        Label(template.title, systemImage: "checklist")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Edit Template") { edit = template }.tint(DS.Color.accent)
                    }
                    .contextMenu {
                        Button("Edit Template", systemImage: "pencil") { edit = template }
                    }
                }
                FormSaveError(message: error)
            } header: {
                Text("Templates")
            } footer: {
                Text("Press and hold a template to edit its checks. These team checks are for pit operations. Follow FIRST’s official robot inspection process at the event.")
            }
            Section("Run History") {
                if matchingRuns.isEmpty {
                    Text("Start a run from a template. Each match has its own checklist history.")
                        .foregroundStyle(.secondary)
                }
                ForEach(matchingRuns) { run in
                    NavigationLink {
                        ChecklistRunView(run: run)
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(run.title).font(.headline)
                            if let label = run.matchLabel { Text(label).font(.footnote).foregroundStyle(.secondary) }
                            Text(run.completed == nil ? "\(run.completedIndices.count)/\(run.items.count) checked" : "Completed")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(run.started, style: .date).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(match.map { "\($0.label) Checks" } ?? "Readiness")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openRun) { ChecklistRunView(run: $0) }
        .sheet(item: $edit) { template in
            ChecklistTemplateEditor(template: template, saved: custom.first { $0.key == template.id })
        }
    }

    private func open(_ template: ChecklistDefinition) {
        if let run = runs.first(where: {
            $0.templateKey == template.id && $0.eventID == eventID &&
            $0.matchKey == match?.key.id && $0.completed == nil
        }) {
            openRun = run
            return
        }
        let run = ChecklistRun(template: template, eventID: eventID, match: match)
        context.insert(run)
        do {
            try saveWorkspace(context, in: shared)
            error = nil
            openRun = run
        } catch {
            context.rollback()
            self.error = "Couldn’t start this checklist. Try again."
        }
    }
}

private struct ChecklistRunView: View {
    let run: ChecklistRun
    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Environment(AuthenticationViewModel.self) private var auth
    @State private var error: String?

    var body: some View {
        List {
            Section {
                if let label = run.matchLabel { LabeledContent("Match", value: label) }
                if let completed = run.completed {
                    LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                    if let name = run.completedBy { LabeledContent("Completed by", value: name) }
                } else {
                    ProgressView(value: Double(run.completedIndices.count), total: Double(max(run.items.count, 1))) {
                        Text("\(run.completedIndices.count) of \(run.items.count) checks")
                    }
                }
            }
            Section("Checks") {
                ForEach(run.items.indices, id: \.self) { index in
                    let checked = run.completedIndices.contains(index)
                    Button {
                        if checked { run.completedIndices.removeAll { $0 == index } }
                        else { run.completedIndices.append(index) }
                        save()
                    } label: {
                        Label(run.items[index], systemImage: checked ? "checkmark.circle.fill" : "circle")
                            .frame(minHeight: 44)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityValue(checked ? "Checked" : "Unchecked")
                    .disabled(run.completed != nil)
                }
            }
            if run.completed == nil {
                Section {
                    Button("Complete Run") {
                        guard run.readyToComplete else { return }
                        run.completed = .now
                        run.completedBy = auth.currentUser?.name
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!run.readyToComplete)
                    FormSaveError(message: error)
                }
            }
        }
        .navigationTitle(run.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        do {
            try saveWorkspace(context, in: shared)
            error = nil
        } catch {
            context.rollback()
            self.error = "Couldn’t save this checklist change. Try again."
        }
    }
}

private struct ChecklistTemplateEditor: View {
    let template: ChecklistDefinition
    let saved: ChecklistTemplate?
    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var items = ""
    @State private var error: String?

    private var lines: [String] {
        items.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Section("One Check per Line") {
                    TextEditor(text: $items).frame(minHeight: 220)
                        .accessibilityLabel("Checklist items, one per line")
                }
                FormSaveError(message: error)
            }
            .navigationTitle("Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let row = saved ?? ChecklistTemplate(key: template.id, title: "", items: [])
                        if saved == nil { context.insert(row) }
                        row.title = title.trimmed
                        row.items = lines
                        do {
                            try saveWorkspace(context, in: shared)
                            dismiss()
                        } catch {
                            context.rollback()
                            self.error = "Couldn’t save this template. Your edits are still here."
                        }
                    }
                    .disabled(title.trimmed.isEmpty || lines.isEmpty)
                }
            }
            .onAppear {
                title = template.title
                items = template.items.joined(separator: "\n")
            }
        }
    }
}
