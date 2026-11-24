import SwiftUI
import UniformTypeIdentifiers

struct TeamTabView: View {
    @Environment(AuthenticationViewModel.self) private var auth
    @Environment(\.teamWorkspace) private var workspace
    @State private var showingInvite = false

    var body: some View {
        List {
            if let team = auth.team {
                Section {
                    TeamIdentity(name: team.name, number: team.number)
                    Link("FIRST Team Profile", destination: URL(string: "https://ftc-events.firstinspires.org/team/\(team.number)")!)
                }
            }
            if let workspace {
                Section("Communication") {
                    NavigationLink { TeamChatView(workspace: workspace) } label: {
                        Label("Team Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink { AnnouncementList(workspace: workspace) } label: {
                        Label("Announcements", systemImage: "megaphone")
                    }
                }
                Section("Membership") {
                    NavigationLink { RosterView(workspace: workspace) } label: {
                        Label("Roster", systemImage: "person.2")
                    }
                    if workspace.team.canCoordinate {
                        Button("Invite a Teammate", systemImage: "person.badge.plus") { showingInvite = true }
                    }
                    Button("Switch or Join a Team", systemImage: "arrow.left.arrow.right", action: auth.switchTeam)
                }
                Section {
                    NavigationLink { SyncStatusView(workspace: workspace) } label: {
                        LabeledContent("Workspace Sync", value: workspace.online ? "Connected" : "Offline")
                    }
                }
                .sheet(isPresented: $showingInvite) { InviteView(workspace: workspace) }
            }
            Section {
                NavigationLink { AccountSettingsView() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Team")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RosterView: View {
    let workspace: SharedWorkspace
    @State private var search = ""
    @State private var selected: AppUser?
    @State private var failure: String?

    private var visible: [AppUser] {
        workspace.members.filter { search.trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(search.trimmed) }
    }

    var body: some View {
        List {
            if visible.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No roster to show" : "No matching members", systemImage: "person.2")
            }
            ForEach(visible) { member in
                NavigationLink {
                    Form {
                        LabeledContent("Name", value: member.name)
                        LabeledContent("Role", value: member.role == "admin" ? "Administrator" : member.role.capitalized)
                        if workspace.team.canCoordinate && member.id != workspace.uid && !["admin", "mentor"].contains(member.role) {
                            Button("Revoke Access", role: .destructive) { selected = member }
                        }
                    }
                    .navigationTitle("Member")
                } label: {
                    HStack(spacing: DS.Spacing.md) {
                        InitialsBadge(name: member.name)
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(member.name).font(.headline)
                            Text(member.role == "admin" ? "Administrator" : member.role.capitalized)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
        .navigationTitle("Roster")
        .searchable(text: $search, prompt: "Find a teammate")
        .alert("Revoke team access?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
               presenting: selected) { member in
            Button("Revoke Access", role: .destructive) {
                Task {
                    do { try await workspace.revoke(member) }
                    catch { failure = "Couldn’t revoke access. Try again." }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.name) will lose access to this team’s workspace.")
        }
        .alert("Membership update failed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }
}

struct InitialsBadge: View {
    let name: String

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first)
        Text(String(initials).uppercased())
            .font(.caption.weight(.semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(DS.Color.accent)
            .background(DS.Color.accent.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct InviteView: View {
    let workspace: SharedWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = "member"
    @State private var saving = false
    @State private var invited = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                if invited {
                    Section("Invitation ready") {
                        Text("Share this workspace code with \(email.trimmed). They can accept it after signing in with that Google email.")
                        ShareLink(item: workspace.team.id) { Label("Share Workspace Code", systemImage: "square.and.arrow.up") }
                    }
                } else {
                    TextField("Google email", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Role", selection: $role) {
                        ForEach(["member", "scout", "viewer"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    FormSaveError(message: failure)
                }
            }
            .navigationTitle("Invite Teammate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(invited ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !invited {
                        Button(saving ? "Saving" : "Create Invitation") {
                            saving = true
                            failure = nil
                            Task {
                                defer { saving = false }
                                do {
                                    try await workspace.invite(email: email, role: role)
                                    invited = true
                                } catch let error as WorkspaceError { failure = error.localizedDescription }
                                catch { failure = "Couldn’t create the invitation. Check your connection." }
                            }
                        }
                        .disabled(email.trimmed.isEmpty || saving || !workspace.online)
                    }
                }
            }
        }
    }
}

struct AccountSettingsView: View {
    @Environment(AuthenticationViewModel.self) private var auth
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @State private var signOut = false
    @State private var archive: LegacyArchive?
    @State private var exporting = false
    @State private var archiveStatus: String?

    var body: some View {
        Form {
            if let user = auth.currentUser {
                Section("Account") {
                    LabeledContent("Name", value: user.name)
                    if !user.email.isEmpty { LabeledContent("Email", value: user.email) }
                    if let team = auth.team { LabeledContent("Team role", value: team.roleLabel) }
                }
            }
            Section("App") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
                LabeledContent("Version", value: "\(version) (\(build))")
                Link("Report an App Issue", destination: URL(string: "https://github.com/absingh-code/FTCTeamHub/issues")!)
            }
            if let googleID = auth.previousGoogleID {
                Section("Legacy records") {
                    Button("Export Previous Workspace", systemImage: "square.and.arrow.up") {
                        do {
                            archive = try LegacyArchive.export(googleID: googleID)
                            exporting = archive != nil
                            archiveStatus = archive == nil ? "No previous workspace belongs to this Google account on this device." : nil
                        } catch {
                            archiveStatus = "Couldn’t open the previous workspace. Its records are still on this device."
                        }
                    }
                    if let archiveStatus { Text(archiveStatus).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section { Button("Sign Out", role: .destructive) { signOut = true } }
            FormSaveError(message: auth.membershipError)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: archive, contentType: .json,
                      defaultFilename: "Team-Hub-legacy-records") { result in
            if case .failure = result { archiveStatus = "Couldn’t export the previous workspace." }
            archive = nil
        }
        .confirmationDialog("Sign out?", isPresented: $signOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive, action: auth.signOut)
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SyncStatusView: View {
    let workspace: SharedWorkspace
    @State private var failure: String?
    @State private var discarding: PendingWorkspaceWrite?

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Team connection", value: workspace.online ? "Connected" : "Offline")
                FormSaveError(message: workspace.syncError ?? failure)
                Button("Reconnect", action: workspace.reconnect)
            }
            Section("Outgoing changes") {
                if workspace.pending.isEmpty { Label("All changes sent", systemImage: "checkmark.circle") }
                ForEach(workspace.pending) { write in
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(write.label).font(.headline)
                        Text(write.text ?? write.record?.key ?? "").lineLimit(2).font(.subheadline)
                        if let error = write.failure {
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Button("Retry") { update { try workspace.retry(write) } }
                                .buttonStyle(.bordered)
                            Button("Discard Pending Edit", role: .destructive) { discarding = write }
                                .buttonStyle(.bordered)
                        } else {
                            Label("Waiting to sync", systemImage: "clock").font(.footnote)
                        }
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
        .navigationTitle("Workspace Sync")
        .confirmationDialog("Discard this pending change?", isPresented: Binding(
            get: { discarding != nil }, set: { if !$0 { discarding = nil } }), presenting: discarding) { item in
            Button("Discard", role: .destructive) { update { try workspace.discard(item) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The workspace will show the server copy. Any later pending edits to the same record will also be removed.")
        }
    }

    private func update(_ operation: () throws -> Void) {
        do { try operation(); failure = nil }
        catch { failure = "Couldn’t update the saved queue." }
    }
}
