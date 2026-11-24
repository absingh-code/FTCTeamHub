import SwiftUI
import SwiftData

struct IdeasListView: View {
    @Query(sort: \Idea.dateCreated, order: .reverse) private var ideas: [Idea]
    @Environment(\.teamWorkspace) private var shared
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
                        Text("\(idea.upvotes + (shared?.votes[idea.id.uuidString]?.count ?? 0)) votes")
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
    @Environment(\.teamWorkspace) private var shared
    @State private var voting = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text(idea.title)
                    .font(DS.Font.headline)
                Text(idea.body)
                    .font(DS.Font.body)
            }
            if let shared {
                Section {
                    let voters = shared.votes[idea.id.uuidString] ?? []
                    let voted = voters.contains(shared.uid)
                    Button {
                        voting = true
                        error = nil
                        Task {
                            defer { voting = false }
                            do { try await shared.toggleVote(idea: idea.id) }
                            catch { self.error = "Couldn’t update your vote. Try again." }
                        }
                    } label: {
                        Label("\(voted ? "Remove Vote" : "Upvote") (\(idea.upvotes + voters.count))",
                              systemImage: voted ? "arrow.up.circle.fill" : "arrow.up.circle")
                    }
                    .disabled(voting || !shared.online || !shared.team.canEdit)
                    FormSaveError(message: error)
                }
            }
        }
        .navigationTitle("Idea")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IdeaFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
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
                            try saveWorkspace(context, in: shared)
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
