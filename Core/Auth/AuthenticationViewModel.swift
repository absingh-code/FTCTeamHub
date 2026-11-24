import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import SwiftUI

struct TeamAccess: Identifiable, Equatable {
    let id: String
    let name: String
    let number: Int
    let role: String

    var canEdit: Bool { role != "viewer" }
    var canCoordinate: Bool { role == "admin" || role == "mentor" }
    var roleLabel: String { role == "admin" ? "Administrator" : role.capitalized }
}

@MainActor
@Observable
final class AuthenticationViewModel {
    enum AuthState {
        case checking
        case signedOut
        case signingIn
        case membership
        case signedIn(AppUser)
        case error(String)
    }

    private(set) var authState: AuthState = .checking
    private(set) var currentUser: AppUser?
    private(set) var teams: [TeamAccess] = []
    private(set) var team: TeamAccess?
    private(set) var workspace: SharedWorkspace?
    private(set) var membershipError: String?
    private(set) var checkingMembership = false
    private(set) var isGoogleConfigured = false
    var isDeviceWorkspace: Bool { workspace == nil }
    var isSigningIn: Bool { if case .signingIn = authState { true } else { false } }

    private var backend: Firestore?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var membershipListener: ListenerRegistration?
    private var generation = UUID()

    func restore() {
        guard authListener == nil, case .checking = authState else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-workspace") {
            let user = AppUser(id: "fixture-member", name: "Taylor Rivera", email: "", role: "Member")
            currentUser = user
            team = TeamAccess(id: "fixture", name: "Wild Circuits", number: 36611, role: "member")
            authState = .signedIn(user)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-login") {
            isGoogleConfigured = true
            authState = .signedOut
            return
        }
        #endif
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let options = FirebaseOptions(contentsOfFile: url.path),
              let clientID = options.clientID, clientID.hasSuffix(".apps.googleusercontent.com"),
              options.bundleID == Bundle.main.bundleIdentifier,
              let config = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
              config.contains(where: {
                  ($0["CFBundleURLSchemes"] as? [String])?.contains(
                      clientID.split(separator: ".").reversed().joined(separator: ".")
                  ) == true
              }) else {
            authState = .signedOut
            return
        }

        FirebaseApp.configure(options: options)
        let db = Firestore.firestore()
        let settings = db.settings
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        backend = db
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        isGoogleConfigured = true
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self, user?.uid == Auth.auth().currentUser?.uid else { return }
                await self.receive(user)
            }
        }
    }

    func signIn() async {
        guard isGoogleConfigured, backend != nil, !isSigningIn else { return }
        guard let presenter = Self.presentationController() else {
            authState = .error("Open the app and try signing in again.")
            return
        }
        authState = .signingIn
        do {
            let google = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter).user
            guard let token = google.idToken?.tokenString else {
                authState = .error("Google did not return an identity token. Try signing in again.")
                return
            }
            let credential = GoogleAuthProvider.credential(withIDToken: token, accessToken: google.accessToken.tokenString)
            _ = try await Auth.auth().signIn(with: credential)
        } catch {
            let failure = error as NSError
            if failure.domain == "com.google.GIDSignIn", failure.code == -5 {
                authState = .signedOut
            } else {
                GIDSignIn.sharedInstance.signOut()
                authState = .error("Couldn’t sign in. Check your connection and try again.")
            }
        }
    }

    func signOut() {
        guard backend != nil else { return }
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            reset()
            authState = .signedOut
        } catch {
            membershipError = "Couldn’t sign out. Try again."
        }
    }

    func switchTeam() {
        closeWorkspace()
        authState = .membership
        Task { await refreshMemberships(autoSelect: false) }
    }

    func refreshMemberships(autoSelect: Bool = true) async {
        guard let db = backend, let user = currentUser, !checkingMembership else { return }
        let request = generation
        checkingMembership = true
        membershipError = nil
        defer { if generation == request { checkingMembership = false } }
        do {
            let refs = try await db.collection("workspaceUsers").document(user.id)
                .collection("memberships").getDocuments(source: .server).documents
            var result: [TeamAccess] = []
            for ref in refs {
                let tenant = db.collection("workspaces").document(ref.documentID)
                let member = try await tenant.collection("members").document(user.id).getDocument(source: .server)
                guard let data = member.data(), data["active"] as? Bool == true,
                      let role = data["role"] as? String else { continue }
                let info = try await tenant.getDocument(source: .server)
                guard let name = info.get("name") as? String, let number = info.get("number") as? Int else { continue }
                result.append(TeamAccess(id: ref.documentID, name: name, number: number, role: role))
            }
            guard request == generation else { return }
            teams = result.sorted { ($0.number, $0.id) < ($1.number, $1.id) }
            let preferred = UserDefaults.standard.string(forKey: "last-team-" + user.id)
            if autoSelect, let choice = teams.first(where: { $0.id == preferred }) ?? (teams.count == 1 ? teams.first : nil) {
                open(choice)
            }
        } catch {
            guard request == generation else { return }
            membershipError = "Couldn’t verify your team access. Connect to the internet and retry."
        }
    }

    func acceptInvite(_ input: String) async throws {
        let key = input.trimmed.lowercased()
        guard let db = backend, let user = currentUser,
              let account = Auth.auth().currentUser, account.uid == user.id, account.isEmailVerified,
              !user.email.isEmpty, !user.email.contains("/"),
              key.range(of: "^[a-z0-9-]{4,64}$", options: .regularExpression) != nil else {
            throw WorkspaceError.message("Enter the workspace code for your verified Google email.")
        }
        let tenant = db.collection("workspaces").document(key)
        let invitation = tenant.collection("invites").document(user.email)
        let invite = try await invitation.getDocument(source: .server)
        guard invite.get("active") as? Bool == true, let role = invite.get("role") as? String else {
            throw WorkspaceError.message("There’s no active invitation for this Google email and workspace code.")
        }
        let member = tenant.collection("members").document(user.id)
        let index = db.collection("workspaceUsers").document(user.id).collection("memberships").document(key)
        let batch = db.batch()
        batch.setData([
            "name": user.name, "role": role, "active": true,
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: member)
        batch.setData(["joinedAt": FieldValue.serverTimestamp()], forDocument: index)
        batch.updateData(["active": false, "acceptedBy": user.id], forDocument: invitation)
        try await batch.commit()
        await refreshMemberships()
    }

    func open(_ access: TeamAccess) {
        guard let current = currentUser, let db = backend, teams.contains(access) else { return }
        closeWorkspace()
        do {
            let shared = try SharedWorkspace(db: db, team: access, uid: current.id)
            workspace = shared
            team = access
            UserDefaults.standard.set(access.id, forKey: "last-team-" + current.id)
            authState = .signedIn(current)
            let listener = shared.tenant.collection("members").document(current.id)
            membershipListener = listener.addSnapshotListener { [weak self, weak shared] snapshot, error in
                Task { @MainActor in
                    guard let self, let shared, self.workspace === shared else { return }
                    if let snapshot, !snapshot.metadata.isFromCache {
                        if snapshot.get("active") as? Bool != true {
                            self.accessChanged("Your access to this team was revoked.")
                        } else if let role = snapshot.get("role") as? String, role != access.role {
                            self.accessChanged("Your team role changed. Reopen the workspace to continue.")
                        }
                    } else if (error as NSError?)?.code == 7 {
                        self.accessChanged("Your team access is no longer available.")
                    }
                }
            }
        } catch {
            membershipError = "Couldn’t open the team’s records on this device. Try again."
        }
    }

    private func receive(_ account: FirebaseAuth.User?) async {
        if let account, account.uid == currentUser?.id { return }
        reset()
        guard let account else {
            authState = .signedOut
            return
        }
        guard account.isEmailVerified, let email = account.email else {
            try? Auth.auth().signOut()
            authState = .error("Use a verified Google account to join a team.")
            return
        }
        currentUser = AppUser(id: account.uid, name: String((account.displayName ?? "Team member").prefix(120)),
                              email: email.lowercased(), role: "", profileImageURL: account.photoURL?.absoluteString)
        authState = .membership
        await refreshMemberships()
    }

    private func accessChanged(_ message: String) {
        closeWorkspace()
        teams = []
        authState = .membership
        membershipError = message
    }

    private func closeWorkspace() {
        membershipListener?.remove()
        membershipListener = nil
        workspace?.stop()
        workspace = nil
        team = nil
    }

    private func reset() {
        closeWorkspace()
        generation = UUID()
        currentUser = nil
        teams = []
        membershipError = nil
        checkingMembership = false
    }

    private static func presentationController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        return presenter
    }
}
