import SwiftUI
import GoogleSignIn

@main
@MainActor
struct FTCTeamHubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthenticationViewModel()
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
                .tint(DS.Color.accent)
                .task { auth.restore() }
                .onOpenURL { _ = GIDSignIn.sharedInstance.handle($0) }
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: Self { self }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
