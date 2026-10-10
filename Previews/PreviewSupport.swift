import SwiftUI
import SwiftData

@MainActor
enum PreviewSupport {
    static var container: ModelContainer = {
        let schema = Schema([
            AppUser.self,
            TaskItem.self,
            NotebookEntry.self,
            ScoutingRecord.self,
            Idea.self,
            InventoryItem.self,
            TeamEventRecord.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])

        let context = container.mainContext

        let user = AppUser(id: "preview-1", name: "Preview User", email: "preview@team.local", role: "Software", isActive: true)
        context.insert(user)

        context.insert(TaskItem(title: "Tune drive PID", assignedToID: "preview-1", status: "inProgress", priority: "high", deadline: .now.addingTimeInterval(86400)))
        context.insert(TaskItem(title: "Update notebook template", assignedToID: "preview-1", status: "todo", priority: "medium"))

        context.insert(InventoryItem(name: "GoBILDA 5203 motor", quantity: 1, lowStockThreshold: 2, location: "Bin A", status: "low"))
        context.insert(InventoryItem(name: "REV Control Hub", quantity: 2, lowStockThreshold: 1, location: "Shelf 1"))

        context.insert(TeamEventRecord(name: "League Meet 1", date: .now.addingTimeInterval(7 * 86400), location: "Local HS"))

        try? context.save()
        return container
    }()
}

#Preview("Today") {
    TodayTabView()
        .modelContainer(PreviewSupport.container)
        .environment(AuthenticationViewModel())
        .preferredColorScheme(.dark)
}
