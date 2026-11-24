import SwiftUI
import SwiftData

struct PitTabView: View {
    @Query(filter: #Predicate<RobotIssue> { $0.status != "Resolved" }) private var issues: [RobotIssue]
    @Query private var inventory: [InventoryItem]

    var body: some View {
        NavigationStack {
            List {
                Section("Robot Operations") {
                    NavigationLink {
                        RobotIssuesView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("Robot Issues")
                                let critical = issues.filter { $0.severity == IssueSeverity.critical.rawValue }.count
                                Text(critical > 0 ? "\(critical) critical unresolved" : "\(issues.count) unresolved")
                                    .font(.footnote).foregroundStyle(critical > 0 ? Color.red : Color.secondary)
                            }
                        } icon: { Image(systemName: "wrench.and.screwdriver") }
                    }
                    NavigationLink {
                        ChecklistHub()
                    } label: { Label("Readiness Checklists", systemImage: "checklist") }
                    NavigationLink {
                        InventoryListView()
                    } label: {
                        Label("Parts Inventory", systemImage: "shippingbox")
                            .badge(inventory.filter { $0.quantity <= $0.lowStockThreshold }.count)
                    }
                }
                Section {
                    Text("Issue progress and readiness runs are visible to teammates after they sync.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pit")
            .listStyle(.insetGrouped)
        }
    }
}

private struct InventoryListView: View {
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]
    @State private var search = ""
    @State private var add = false
    @State private var filter = "All"

    private var filtered: [InventoryItem] {
        items.filter { item in
            (search.trimmed.isEmpty || item.name.localizedCaseInsensitiveContains(search.trimmed) ||
             item.location.localizedCaseInsensitiveContains(search.trimmed)) &&
            (filter == "All" || (filter == "Low stock" && item.quantity <= item.lowStockThreshold) ||
             (filter == "Maintenance" && item.status == "maintenance"))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(["All", "Low stock", "Maintenance"], id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Parts") {
                if filtered.isEmpty {
                    Text(items.isEmpty ? "Add a part to track where it is and how many you have." : "No parts match those filters.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { item in
                    NavigationLink {
                        InventoryEditor(item: item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(item.name)
                                if !item.location.trimmed.isEmpty {
                                    Text(item.location).font(.footnote).foregroundStyle(.secondary)
                                }
                                if item.quantity <= item.lowStockThreshold {
                                    StatusLabel(title: "Low Stock", icon: "exclamationmark.triangle", color: .orange)
                                }
                            }
                            Spacer()
                            Text(item.quantity, format: .number).font(DS.Font.number)
                                .accessibilityLabel("\(item.quantity) in stock")
                        }
                    }
                }
            }
        }
        .navigationTitle("Inventory")
        .searchable(text: $search, prompt: "Part name or storage location")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Part", systemImage: "plus") { add = true }
            }
        }
        .sheet(isPresented: $add) { NavigationStack { InventoryEditor() } }
    }
}

struct InventoryEditor: View {
    var item: InventoryItem?

    @Environment(\.modelContext) private var context
    @Environment(\.teamWorkspace) private var shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var threshold = 2
    @State private var location = ""
    @State private var status = "ok"
    @State private var deleteConfirm = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Part") {
                TextField("Name", text: $name)
                TextField("Location", text: $location)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 0...max(quantity, 9999))
                Stepper("Low-stock threshold: \(threshold)", value: $threshold, in: 0...max(threshold, 9999))
                Picker("Status", selection: $status) {
                    Text("OK").tag("ok")
                    Text("Low").tag("low")
                    Text("Maintenance").tag("maintenance")
                }
            }
            if item != nil {
                Section { Button("Delete Part", role: .destructive) { deleteConfirm = true } }
            }
            if let item, let shared {
                Section("Stock History") {
                    NavigationLink("View Recent Changes") {
                        StockHistoryView(item: item, workspace: shared)
                    }
                }
            }
            FormSaveError(message: error)
        }
        .navigationTitle(item == nil ? "Add Part" : "Part Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(name.trimmed.isEmpty || shared?.team.canEdit == false)
            }
            if item == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .confirmationDialog("Delete this part?", isPresented: $deleteConfirm, titleVisibility: .visible) {
            Button("Delete Part", role: .destructive) {
                if let item { context.delete(item); persist() }
            }
        }
        .onAppear {
            if let item {
                name = item.name
                quantity = max(0, item.quantity)
                threshold = max(0, item.lowStockThreshold)
                location = item.location
                status = item.status
            }
        }
    }

    private func save() {
        let row = item ?? InventoryItem(name: name.trimmed)
        if item == nil { context.insert(row) }
        row.name = name.trimmed
        row.quantity = quantity
        row.lowStockThreshold = threshold
        row.location = location.trimmed
        row.status = status
        row.lastChecked = .now
        persist()
    }

    private func persist() {
        do {
            try saveWorkspace(context, in: shared)
            dismiss()
        } catch {
            context.rollback()
            self.error = "Couldn’t update inventory. Your edits are still here."
        }
    }
}

private struct StockHistoryView: View {
    let item: InventoryItem
    let workspace: SharedWorkspace
    @State private var changes: [StockChange]?
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                DataNotice(title: "History unavailable", detail: error, icon: "clock.arrow.circlepath") {
                    Task { await load() }
                }
            }
            if let changes {
                if changes.isEmpty { Text("No quantity changes recorded.").foregroundStyle(.secondary) }
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("\(change.before) → \(change.after) in stock").font(.headline)
                        Text(workspace.members.first { $0.id == change.actor }?.name ?? "Former or unavailable member")
                        Text(change.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            } else if error == nil {
                ProgressView("Loading stock history")
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { changes = try await workspace.stockChanges(item: item.id); error = nil }
        catch { self.error = "Connect to the team workspace and try again." }
    }
}
