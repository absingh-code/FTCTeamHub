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
        case .membership:
            MembershipView()
        case .signedIn(let user):
            if let team = auth.team, let workspace = auth.workspace {
                if workspace.recordsReady {
                    MainTabView(team: team, scope: user.id + ":" + team.id)
                        .modelContainer(workspace.container)
                        .environment(\.teamWorkspace, workspace)
                        .id(user.id + ":" + team.id)
                } else {
                    VStack(spacing: DS.Spacing.lg) {
                        if let error = workspace.syncError {
                            DataNotice(title: "Workspace unavailable", detail: error,
                                       icon: "arrow.trianglehead.clockwise", retry: workspace.reconnect)
                        } else {
                            ProgressView("Loading \(team.name)")
                        }
                        Button("Team Access", action: auth.switchTeam)
                        Button("Sign Out", action: auth.signOut)
                    }
                    .padding()
                }
            } else {
                #if DEBUG
                if let team = auth.team {
                    MainTabView(team: team, scope: "ui-testing")
                        .modelContainer(PreviewSupport.container)
                }
                #endif
            }
        }
    }
}

@MainActor
struct MainTabView: View {
    let team: TeamAccess
    @State private var selectedTab: Tab = .today
    @State private var competition: CompetitionWorkspace

    init(team: TeamAccess, scope: String) {
        self.team = team
        _competition = State(initialValue: CompetitionWorkspace(teamNumber: team.number, scope: scope))
    }

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
                .tabItem { Label("Scout", systemImage: "binoculars") }
                .tag(Tab.scout)
            WorkTabView()
                .tabItem { Label("Work", systemImage: "checklist") }
                .tag(Tab.work)
            PitTabView()
                .tabItem { Label("Pit", systemImage: "wrench.and.screwdriver") }
                .tag(Tab.pit)
        }
        .environment(competition)
        .task(id: competition.season) { await competition.loadEvents() }
        .task(id: competition.selected?.id) { await competition.loadSelected() }
    }
}
