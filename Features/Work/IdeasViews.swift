import SwiftUI
import SwiftData

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
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $bodyText, axis: .vertical)
                    .lineLimit(4...10)
                FormSaveError(message: saveError)
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
                        do {
                            try context.save()
                            dismiss()
                        } catch {
                            context.rollback()
                            saveError = "Couldn’t save this idea. Your edits are still here."
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
