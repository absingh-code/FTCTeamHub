import SwiftUI
import SwiftData

@MainActor
enum PreviewSupport {
    static let container: ModelContainer = {
        let schema = WorkspaceStore.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}

#Preview("Sign In") {
    AuthenticationView()
        .environment(AuthenticationViewModel())
}

#Preview("Today") {
    TodayTabView(openTab: { _ in })
        .modelContainer(PreviewSupport.container)
        .environment(AuthenticationViewModel())
        .environment(CompetitionWorkspace())
}
#if DEBUG
extension PreviewSupport {
    static let fixtureContainer: ModelContainer = {
        let schema = WorkspaceStore.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let db = container.mainContext
        db.insert(TaskItem(title: "Verify the intake after the spacer change", assignedToID: "fixture-member",
                           status: "inProgress", priority: "high", deadline: .now, tags: ["Intake"]))
        db.insert(TaskItem(title: "Pack the spare controller", assignedToID: "fixture-member",
                           priority: "medium", tags: ["Drive team"]))
        db.insert(TaskItem(title: "Review autonomous starts", status: "done", tags: ["Software"]))
        db.insert(InventoryItem(name: "M3 locknuts", quantity: 2, lowStockThreshold: 6, location: "Pit case A"))
        db.insert(InventoryItem(name: "Servo extensions", quantity: 14, location: "Electrical drawer"))
        try! db.save()
        return container
    }()
}

struct PreviewWorkspace: View {
    let team: TeamAccess
    @State private var competition = CompetitionWorkspace()
    private let event = FTCEvent(season: 2026, code: "FIXTURE", name: "Southern League Meet",
        start: "2026-11-15", end: "2026-11-15", timezone: "America/New_York", location: nil, modifiedRules: false)
    private let example = FTCMatch(eventSeason: 2026, eventCode: "FIXTURE", id: 12, hasBeenPlayed: false,
        scheduledStartTime: nil, actualStartTime: nil, tournamentLevel: "Quals", series: nil,
        scores: nil, teams: [.init(teamNumber: 36611, alliance: "Red", station: "One", onField: true,
                                  noShow: false, dq: false, surrogate: false)])

    var body: some View {
        switch ProcessInfo.processInfo.arguments.last(where: { $0.hasPrefix("--screen=") }) {
        case "--screen=chat":
            NavigationStack { transcript }
        case "--screen=profile":
            NavigationStack {
                TeamProfileView(number: 36611, event: event, directory: TeamDirectory(names: [36611: "Wild Circuits"]),
                                stats: .init(rank: 2, qualMatchesPlayed: 5, wins: 4, losses: 1, ties: 0,
                                             opr: .init(totalPoints: 30.4, totalPointsNp: 24.7, autoPoints: 6.1)),
                                matches: [example], useLiveProvider: false)
            }
            .environment(competition)
        case "--screen=scouting":
            MatchReportStart(target: ScoutTarget(match: example, team: 36611))
        default:
            MainTabView(team: team, scope: "ui-testing")
        }
    }

    private var transcript: some View {
        let reference = Date(timeIntervalSince1970: 1_794_764_400)
        let messages = [
            WorkspaceMessage(id: "fixture-1", sender: "morgan", text: "Queue opens in ten minutes. Bring the spare controller and meet at the pit table.",
                             link: nil, date: reference),
            WorkspaceMessage(id: "fixture-2", sender: "taylor", text: "I’ll bring it. The checklist is ready for review.",
                             link: nil, date: reference.addingTimeInterval(60)),
            WorkspaceMessage(id: "fixture-3", sender: "morgan", text: "Thanks. We’ll verify the intake before heading over.",
                             link: nil, date: reference.addingTimeInterval(120))
        ]
        return ScrollView {
            LazyVStack(spacing: DS.Spacing.md) {
                ForEach(messages) { message in
                    ConversationBubble(message: message,
                                       name: message.sender == "taylor" ? "You" : "Morgan Lee",
                                       mine: message.sender == "taylor")
                }
            }
            .padding(DS.Spacing.lg)
        }
        .navigationTitle("Team Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
