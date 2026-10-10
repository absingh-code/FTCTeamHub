import Foundation
import GoogleSignIn
import SwiftUI

@MainActor
@Observable
final class AuthenticationViewModel {
    static let shared = AuthenticationViewModel()

    enum AuthState: Equatable {
        case checking
        case signedOut
        case signingIn
        case signedIn(AppUser)
        case error(String)
    }

    private(set) var authState: AuthState = .checking
    private(set) var currentUser: AppUser?

    init() {
        Task { await restore() }
    }

    func restore() async {
        do {
            if let user = try await restorePreviousSignIn() {
                let mapped = map(user)
                currentUser = mapped
                authState = .signedIn(mapped)
            } else {
                authState = .signedOut
            }
        } catch {
            authState = .signedOut
        }
    }

    func handleRestoredUser(_ gUser: GIDGoogleUser) {
        let mapped = map(gUser)
        currentUser = mapped
        authState = .signedIn(mapped)
    }

    func signIn(presenting: UIViewController) async {
        authState = .signingIn
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
            let mapped = map(result.user)
            currentUser = mapped
            authState = .signedIn(mapped)
        } catch {
            authState = .error(error.localizedDescription)
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        authState = .signedOut
    }

    private func map(_ gUser: GIDGoogleUser) -> AppUser {
        AppUser(
            id: gUser.userID ?? UUID().uuidString,
            name: gUser.profile?.name ?? "Unknown",
            email: gUser.profile?.email ?? "",
            role: "Software",
            profileImageURL: gUser.profile?.imageURL(withDimension: 128)?.absoluteString,
            googleToken: gUser.idToken?.tokenString,
            isActive: true,
            lastSeen: .now
        )
    }

    private func restorePreviousSignIn() async throws -> GIDGoogleUser? {
        try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: user)
                }
            }
        }
    }
}
