import SwiftUI

struct ContentView: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    var body: some View {
        Group {
            switch authVM.authState {
            case .checking:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Color.background)
            case .signedOut, .error:
                AuthenticationView()
            case .signingIn:
                ProgressView("Signing in…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Color.background)
            case .signedIn:
                MainTabView()
            }
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: Tab = .today

    enum Tab: Hashable {
        case today, work, pit, scout, team
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayTabView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)

            WorkTabView()
                .tabItem { Label("Work", systemImage: "checklist") }
                .tag(Tab.work)

            PitTabView()
                .tabItem { Label("Pit", systemImage: "wrench.and.screwdriver") }
                .tag(Tab.pit)

            ScoutTabView()
                .tabItem { Label("Scout", systemImage: "chart.bar") }
                .tag(Tab.scout)

            TeamTabView()
                .tabItem { Label("Team", systemImage: "person.2") }
                .tag(Tab.team)
        }
        .tint(DS.Color.accent)
    }
}
