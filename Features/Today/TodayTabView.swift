import SwiftUI
import SwiftData

struct TodayTabView: View {
    @Query private var tasks: [TaskItem]
    @Query private var events: [TeamEventRecord]
    @Query private var inventory: [InventoryItem]
    @Environment(AuthenticationViewModel.self) private var authVM

    private var myOpenTasks: [TaskItem] {
        guard let uid = authVM.currentUser?.id else { return [] }
        return tasks
            .filter { $0.assignedToID == uid && $0.status != "done" }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    private var lowStock: [InventoryItem] {
        inventory.filter { $0.quantity <= $0.lowStockThreshold }
    }

    private var upcomingEvents: [TeamEventRecord] {
        events
            .filter { $0.date >= Calendar.current.startOfDay(for: .now) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if !myOpenTasks.isEmpty {
                    Section("Assigned to you") {
                        ForEach(myOpenTasks) { task in
                            NavigationLink(value: task) {
                                TaskRow(task: task)
                            }
                        }
                    }
                }

                if !upcomingEvents.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcomingEvents.prefix(5)) { event in
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(event.name)
                                    .font(DS.Font.body)
                                    .foregroundStyle(DS.Color.labelPrimary)
                                Text(event.date, style: .date)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.labelSecondary)
                            }
                            .padding(.vertical, DS.Spacing.xs)
                        }
                    }
                }

                if !lowStock.isEmpty {
                    Section("Inventory alerts") {
                        ForEach(lowStock) { item in
                            HStack {
                                Text(item.name)
                                    .font(DS.Font.body)
                                Spacer()
                                Text("\(item.quantity)")
                                    .font(DS.Font.number)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if myOpenTasks.isEmpty && upcomingEvents.isEmpty && lowStock.isEmpty {
                    ContentUnavailableView(
                        "Nothing scheduled",
                        systemImage: "calendar",
                        description: Text("Assigned tasks and events will appear here.")
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .navigationTitle("Today")
            .navigationDestination(for: TaskItem.self) { task in
                TaskDetailView(task: task)
            }
        }
    }
}

struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(task.title)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.labelPrimary)
            HStack(spacing: DS.Spacing.sm) {
                Text(task.priority.capitalized)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.labelSecondary)
                if let deadline = task.deadline {
                    Text(deadline, style: .date)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.labelTertiary)
                }
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
