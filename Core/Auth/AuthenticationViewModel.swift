import Foundation
import GoogleSignIn
import SwiftUI

@MainActor
@Observable
final class AuthenticationViewModel {
    enum AuthState {
        case checking
        case signedOut
        case signingIn
        case signedIn(AppUser)
        case error(String)
    }

    private(set) var authState: AuthState = .checking
    private(set) var currentUser: AppUser?
    private(set) var isDeviceWorkspace = false

    private static let deviceWorkspaceID = "device-workspace"
    private static let devicePreference = "useDeviceWorkspace"

    private var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              value.hasSuffix(".apps.googleusercontent.com"),
              !value.contains("YOUR_"), !value.hasPrefix("$("),
              value.count > ".apps.googleusercontent.com".count else { return nil }
        let scheme = value.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        guard types?.contains(where: {
            ($0["CFBundleURLSchemes"] as? [String])?.contains(scheme) == true
        }) == true else { return nil }
        return value
    }

    var isGoogleConfigured: Bool { clientID != nil }
    var isSigningIn: Bool {
        if case .signingIn = authState { true } else { false }
    }

    func restore() async {
        guard case .checking = authState else { return }
        if UserDefaults.standard.bool(forKey: Self.devicePreference) {
            openDeviceWorkspace()
            return
        }
        guard let clientID else {
            authState = .signedOut
            return
        }

        let service = GIDSignIn.sharedInstance
        service.configuration = GIDConfiguration(clientID: clientID)
        do {
            let user: GIDGoogleUser? = try await withCheckedThrowingContinuation { continuation in
                service.restorePreviousSignIn { user, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: user) }
                }
            }
            if let user { try accept(user) }
            else { authState = .signedOut }
        } catch {
            authState = .signedOut
        }
    }

    func signIn() async {
        guard !isSigningIn, let clientID else { return }
        guard let controller = Self.presentationController() else {
            authState = .error("Sign-in couldn’t open. Try again when the app is active.")
            return
        }
        authState = .signingIn
        let service = GIDSignIn.sharedInstance
        service.configuration = GIDConfiguration(clientID: clientID)

        do {
            let result = try await service.signIn(withPresenting: controller)
            try accept(result.user)
        } catch {
            let failure = error as NSError
            if failure.domain == "com.google.GIDSignIn", failure.code == -5 {
                authState = .signedOut
            } else {
                authState = .error("Google couldn’t complete sign-in. Check your connection and try again.")
            }
        }
    }

    func openDeviceWorkspace() {
        guard !isSigningIn else { return }
        UserDefaults.standard.set(true, forKey: Self.devicePreference)
        let user = AppUser(id: Self.deviceWorkspaceID, name: "On this device", email: "", role: "Local workspace")
        currentUser = user
        isDeviceWorkspace = true
        authState = .signedIn(user)
    }

    func signOut() {
        if !isDeviceWorkspace { GIDSignIn.sharedInstance.signOut() }
        UserDefaults.standard.removeObject(forKey: Self.devicePreference)
        currentUser = nil
        isDeviceWorkspace = false
        authState = .signedOut
    }

    private func accept(_ account: GIDGoogleUser) throws {
        guard let id = account.userID, !id.isEmpty else {
            throw CocoaError(.userCancelled)
        }
        let user = AppUser(
            id: id,
            name: account.profile?.name ?? "Google account",
            email: account.profile?.email ?? "",
            role: "Google identity",
            profileImageURL: account.profile?.imageURL(withDimension: 128)?.absoluteString
        )
        UserDefaults.standard.removeObject(forKey: Self.devicePreference)
        currentUser = user
        isDeviceWorkspace = false
        authState = .signedIn(user)
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
