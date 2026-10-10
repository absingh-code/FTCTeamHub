import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct FTCTeamHubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authVM = AuthenticationViewModel()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AppUser.self,
            TaskItem.self,
            NotebookEntry.self,
            ScoutingRecord.self,
            Idea.self,
            InventoryItem.self,
            TeamEventRecord.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authVM)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
