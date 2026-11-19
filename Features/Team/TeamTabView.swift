import SwiftUI
import SwiftData
import Network

struct TeamTabView: View {
    @Environment(AuthenticationViewModel.self) private var auth
    @Environment(CompetitionWorkspace.self) private var competition
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @Query(sort: \AppUser.name) private var members: [AppUser]
    @State private var signOut = false
    @State private var showingContact = false

    var body: some View {
        List {
            Section("Team") {
                TeamIdentity()
                Link("FIRST Team Profile", destination: URL(string: "https://ftc-events.firstinspires.org/team/36611")!)
            }
            Section("Workspace") {
                if let user = auth.currentUser {
                    LabeledContent("Identity", value: user.name)
                    if !user.email.isEmpty { LabeledContent("Email", value: user.email) }
                    LabeledContent("Access", value: user.role)
                }
                Text("Team records are stored in this workspace on this device. Public competition data comes from FTCScout.")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Connection", value: competition.connection.label)
                if let updated = competition.detail?.lastUpdated {
                    LabeledContent("Event data fetched", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("Local Contacts") {
                if members.isEmpty {
                    Text("Add names for local task assignments.").foregroundStyle(.secondary)
                }
                ForEach(members) { member in
                    LabeledContent(member.name, value: member.role)
                }
                Button("Add Local Contact", systemImage: "person.badge.plus") { showingContact = true }
            }
            Section("App") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                LabeledContent("Version", value: appVersion)
                Link("Report an App Issue", destination: URL(string: "https://github.com/absingh-code/FTCTeamHub/issues")!)
            }
            Section {
                Button(auth.isDeviceWorkspace ? "Close Workspace" : "Sign Out", role: .destructive) { signOut = true }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(auth.isDeviceWorkspace ? "Close this workspace?" : "Sign out of Google?",
                            isPresented: $signOut, titleVisibility: .visible) {
            Button(auth.isDeviceWorkspace ? "Close Workspace" : "Sign Out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saved records stay in the current workspace on this device.") }
        .sheet(isPresented: $showingContact) { ContactForm() }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct ContactForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = "Member"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Team area", selection: $role) {
                    ForEach(["Member", "Software", "Hardware", "Strategy", "Scout"], id: \.self) { Text($0).tag($0) }
                }
                Text("This contact is for task assignment on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
                FormSaveError(message: error)
            }
            .navigationTitle("Add Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.insert(AppUser(id: "contact:" + UUID().uuidString, name: name.trimmed, email: "", role: role))
                        do {
                            try context.save()
                            dismiss()
                        } catch {
                            context.rollback()
                            self.error = "Couldn’t save this contact. Try again."
                        }
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
    }
}

enum ConnectionState: String {
    case checking
    case available
    case offline

    var label: String {
        switch self {
        case .checking: "Checking"
        case .available: "Network available"
        case .offline: "Offline"
        }
    }
}
