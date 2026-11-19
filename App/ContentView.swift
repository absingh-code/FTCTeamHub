import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthenticationViewModel.self) private var auth

    var body: some View {
        switch auth.authState {
        case .checking:
            ProgressView("Restoring session")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.background)
        case .signedOut, .signingIn, .error:
            AuthenticationView()
        case .signedIn(let user):
            WorkspaceRoot(user: user, isDeviceWorkspace: auth.isDeviceWorkspace)
                .id(user.id)
        }
    }
}

private struct WorkspaceRoot: View {
    let user: AppUser
    let isDeviceWorkspace: Bool
    @State private var container: ModelContainer?
    @State private var loadFailed = false
    @State private var attempt = 0
    @Environment(AuthenticationViewModel.self) private var auth

    var body: some View {
        Group {
            if let container {
                MainTabView()
                    .modelContainer(container)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Workspace unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("The app couldn’t open your workspace. Your original records are kept on this device.")
                } actions: {
                    Button("Try Again") { attempt += 1 }
                        .buttonStyle(.borderedProminent)
                    Button("Back to Sign In") { auth.signOut() }
                }
            } else {
                ProgressView("Opening workspace")
            }
        }
        .task(id: attempt) {
            loadFailed = false
            do {
                container = try WorkspaceStore.open(for: user.id, local: isDeviceWorkspace)
            } catch {
                loadFailed = true
            }
        }
    }
}

@MainActor
struct MainTabView: View {
    @State private var selectedTab: Tab = .today
    @State private var competition = CompetitionWorkspace()

    enum Tab: Hashable {
        case today, competition, scout, work, pit
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayTabView(openTab: { selectedTab = $0 })
                .tabItem { Label("Today", systemImage: "house") }
                .tag(Tab.today)
            CompetitionTabView()
                .tabItem { Label("Compete", systemImage: "flag.checkered") }
                .tag(Tab.competition)
            ScoutTabView()
                .tabItem { Label("Scout", systemImage: "binoculars.fill") }
                .tag(Tab.scout)
            WorkTabView()
                .tabItem { Label("Work", systemImage: "checklist") }
                .tag(Tab.work)
            PitTabView()
                .tabItem { Label("Pit", systemImage: "wrench.and.screwdriver.fill") }
                .tag(Tab.pit)
        }
        .environment(competition)
        .task(id: competition.season) { await competition.loadEvents() }
        .task(id: competition.selected?.id) { await competition.loadSelected() }
    }
}
