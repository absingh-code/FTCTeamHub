import UIKit
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            // Allow running without Google credentials for previews / local testing
            print("GIDClientID not found in Info.plist — Google Sign-In disabled")
            return true
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let error {
                print("Google Sign-In restore failed: \(error.localizedDescription)")
            } else if let user {
                Task { @MainActor in
                    AuthenticationViewModel.shared.handleRestoredUser(user)
                }
            }
        }
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}
