import SwiftUI

struct TeamChatView: View {
    let workspace: SharedWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var failure: String?
    @State private var composerReady = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Spacing.md) {
                    if let error = workspace.chatError {
                        DataNotice(title: "Conversation unavailable", detail: error,
                                   icon: "bubble.left", retry: {
                            workspace.openChat()
                            if workspace.historyAvailable { Task { await workspace.loadEarlierMessages() } }
                        })
                    }
                    if workspace.historyAvailable {
                        Button(workspace.loadingHistory ? "Loading messages" : "Load Earlier Messages") {
                            Task { await workspace.loadEarlierMessages() }
                        }
                        .disabled(workspace.loadingHistory)
                    }
                    if workspace.messages.isEmpty {
                        if workspace.messagesReady {
                            ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right",
                                                   description: Text("Start the team conversation."))
                        } else if workspace.chatError == nil {
                            ProgressView("Loading conversation").padding()
                        }
                    }
                    ForEach(workspace.messages) { message in
                        messageRow(message)
                    }
                    Color.clear.frame(height: 1).id("latest")
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: workspace.messages.last?.id) { _, _ in
                if reduceMotion { proxy.scrollTo("latest", anchor: .bottom) }
                else { withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("latest", anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo("latest", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if workspace.team.canEdit { composer }
        }
        .navigationTitle("Team Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            draft = workspace.loadChatDraft()
            composerReady = true
            workspace.openChat()
        }
        .onDisappear { workspace.closeChat() }
        .onChange(of: draft) { _, value in
            guard composerReady else { return }
            do { try workspace.saveChatDraft(value) }
            catch { failure = "Couldn’t keep a copy of the draft on this device." }
        }
    }

    private func messageRow(_ message: WorkspaceMessage) -> some View {
        let mine = message.sender == workspace.uid
        let name = mine ? "You" : (workspace.members.first { $0.id == message.sender }?.name ?? "Former or unavailable member")
        return ConversationBubble(message: message, name: name, mine: mine, retry: {
            guard let write = workspace.pending.first(where: { $0.id == message.id }) else { return }
            do { try workspace.retry(write); failure = nil }
            catch { failure = "Couldn’t retry the message." }
        })
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if !workspace.online {
                Label("Offline. Messages will wait to send.", systemImage: "wifi.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            FormSaveError(message: failure)
            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(DS.Spacing.md)
                    .frame(minHeight: DS.Control.minimum)
                    .background(DS.Color.raised, in: RoundedRectangle(cornerRadius: DS.Radius.control))
                Button {
                    do {
                        try workspace.enqueueMessage(draft)
                        draft = ""
                        failure = nil
                    } catch let error as WorkspaceError { failure = error.localizedDescription }
                    catch { failure = "Couldn’t save this message for sending." }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .frame(width: DS.Control.minimum, height: DS.Control.minimum)
                }
                .accessibilityLabel("Send Message")
                .disabled(draft.trimmed.isEmpty)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(.regularMaterial)
    }
}

struct ConversationBubble: View {
    let message: WorkspaceMessage
    let name: String
    let mine: Bool
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                Text(name).font(.caption.weight(.medium))
                Text(message.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(mine ? DS.Color.accent.opacity(0.16) : DS.Color.surface,
                            in: RoundedRectangle(cornerRadius: DS.Radius.row))
            if message.delivery == .sending {
                Label("Waiting to send", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            } else if message.delivery == .failed, let retry {
                Button("Retry Message", systemImage: "exclamationmark.circle", action: retry).font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }
}

struct AnnouncementList: View {
    let workspace: SharedWorkspace
    @State private var composing = false

    var body: some View {
        List {
            if workspace.announcements.isEmpty {
                ContentUnavailableView("No announcements", systemImage: "megaphone")
            }
            ForEach(workspace.announcements) { announcement in
                AnnouncementRow(announcement: announcement)
            }
        }
        .navigationTitle("Announcements")
        .toolbar {
            if workspace.team.canCoordinate {
                Button("New Announcement", systemImage: "square.and.pencil") { composing = true }
            }
        }
        .sheet(isPresented: $composing) { AnnouncementForm(workspace: workspace) }
    }
}

struct AnnouncementRow: View {
    let announcement: WorkspaceMessage

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(announcement.text)
            Text(announcement.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.footnote).foregroundStyle(.secondary)
            if let value = announcement.link, let url = URL(string: value), url.scheme == "https" {
                Link(destination: url) { Label(url.host ?? "Open Resource", systemImage: "arrow.up.right") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

private struct AnnouncementForm: View {
    let workspace: SharedWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var link = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Announcement", text: $text, axis: .vertical).lineLimit(4...10)
                TextField("Resource link (optional)", text: $link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                FormSaveError(message: error)
            }
            .navigationTitle("New Announcement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        do {
                            try workspace.enqueueMessage(text, announcement: true, link: link.trimmed.isEmpty ? nil : link.trimmed)
                            dismiss()
                        } catch let issue as WorkspaceError { error = issue.localizedDescription }
                        catch { self.error = "Couldn’t save the announcement for sending." }
                    }
                    .disabled(text.trimmed.isEmpty)
                }
            }
        }
    }
}
