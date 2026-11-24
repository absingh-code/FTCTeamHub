import GoogleSignInSwift
import SwiftUI

struct AuthenticationView: View {
    @Environment(AuthenticationViewModel.self) private var auth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                TeamIdentity(name: "Wild Circuits", number: 36611)
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Team Hub").font(DS.Font.display).accessibilityAddTraits(.isHeader)
                    Text("Coordinate matches, share scouting and keep the robot ready.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                if auth.isGoogleConfigured {
                    GoogleSignInButton(scheme: .light, style: .wide, state: auth.isSigningIn ? .disabled : .normal) {
                        Task { await auth.signIn() }
                    }
                    .frame(minHeight: DS.Control.minimum)
                    .accessibilityIdentifier("google-sign-in")
                } else {
                    DataNotice(title: "Sign-in unavailable",
                               detail: "This build needs its Firebase and Google Sign-In configuration. Contact your team administrator for a configured build.",
                               icon: "person.crop.circle.badge.exclamationmark", retry: nil)
                }
                if auth.isSigningIn { ProgressView("Signing in") }
                if case .error(let message) = auth.authState { FormSaveError(message: message) }
            }
            .frame(maxWidth: 400, alignment: .leading)
            .padding(DS.Spacing.xxl)
            .padding(.top, DS.Spacing.xxxl)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Color.background)
    }
}

struct MembershipView: View {
    @Environment(AuthenticationViewModel.self) private var auth
    @State private var code = ""
    @State private var joining = false
    @State private var joinError: String?

    var body: some View {
        NavigationStack {
            Form {
                if let user = auth.currentUser {
                    Section("Signed in") {
                        Text(user.name).font(.headline)
                        Text(user.email).foregroundStyle(.secondary)
                    }
                }
                if auth.checkingMembership { ProgressView("Checking team access") }
                FormSaveError(message: auth.membershipError)
                if !auth.teams.isEmpty {
                    Section("Your teams") {
                        ForEach(auth.teams) { team in
                            Button {
                                auth.open(team)
                            } label: {
                                TeamIdentity(name: team.name, number: team.number)
                            }
                        }
                    }
                }
                Section {
                    TextField("Workspace code", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(joining ? "Accepting invitation" : "Accept Invitation") {
                        joining = true
                        joinError = nil
                        Task {
                            defer { joining = false }
                            do { try await auth.acceptInvite(code) }
                            catch let error as WorkspaceError { joinError = error.localizedDescription }
                            catch { joinError = "Couldn’t accept the invitation. Check the code and your connection." }
                        }
                    }
                    .disabled(code.trimmed.isEmpty || joining || auth.checkingMembership)
                    FormSaveError(message: joinError)
                } header: {
                    Text("Join your team")
                } footer: {
                    Text("Ask a team administrator to invite this Google email and send you the workspace code.")
                }
                Button("Check Team Access Again") { Task { await auth.refreshMemberships() } }
                    .disabled(auth.checkingMembership || joining)
            }
            .navigationTitle("Team Access")
            .toolbar { Button("Sign Out", action: auth.signOut).disabled(joining) }
        }
    }
}
