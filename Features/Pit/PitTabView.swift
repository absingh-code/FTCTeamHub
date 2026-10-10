import SwiftUI
import SwiftData

struct PitTabView: View {
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]
    @State private var search = ""
    @State private var showingAdd = false
    @State private var showingScanner = false
    @State private var filterStatus = "all"

    var filtered: [InventoryItem] {
        var result = items
        if !search.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        if filterStatus != "all" {
            result = result.filter { $0.status == filterStatus }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { item in
                    NavigationLink {
                        InventoryDetailView(item: item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(item.name)
                                    .font(DS.Font.body)
                                    .foregroundStyle(DS.Color.labelPrimary)
                                Text(item.location.isEmpty ? "No location" : item.location)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.labelSecondary)
                            }
                            Spacer()
                            Text("\(item.quantity)")
                                .font(DS.Font.number)
                                .foregroundStyle(item.quantity <= item.lowStockThreshold ? .orange : DS.Color.labelPrimary)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .searchable(text: $search, prompt: "Search parts")
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No inventory",
                        systemImage: "shippingbox",
                        description: Text("Add parts to track quantities and maintenance.")
                    )
                }
            }
            .navigationTitle("Pit")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                InventoryFormView()
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        // Deletion requires confirmation in production; simple remove for now
        for index in offsets {
            // Actual delete handled in detail view with confirmation
        }
    }
}

struct InventoryDetailView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $item.name)
                Stepper("Quantity: \(item.quantity)", value: $item.quantity, in: 0...999)
                Stepper("Low-stock threshold: \(item.lowStockThreshold)", value: $item.lowStockThreshold, in: 0...99)
                TextField("Location", text: $item.location)
                Picker("Status", selection: $item.status) {
                    Text("OK").tag("ok")
                    Text("Low").tag("low")
                    Text("Maintenance").tag("maintenance")
                }
            }
            Section {
                Button("Delete item", role: .destructive) {
                    showingDeleteConfirm = true
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    item.lastChecked = .now
                    try? context.save()
                    dismiss()
                }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(item)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct InventoryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantity = 1
    @State private var threshold = 2
    @State private var location = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 0...999)
                Stepper("Low-stock threshold: \(threshold)", value: $threshold, in: 0...99)
                TextField("Location", text: $location)
            }
            .navigationTitle("Add part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let item = InventoryItem(
                            name: name,
                            quantity: quantity,
                            lowStockThreshold: threshold,
                            location: location,
                            lastChecked: .now
                        )
                        context.insert(item)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// Minimal QR scanner placeholder — replace with AVCaptureSession in production
struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedCode: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xxl) {
                Spacer()
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(DS.Color.labelSecondary)
                Text("Point camera at a part QR code")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.labelSecondary)
                if let code = scannedCode {
                    Text(code)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.labelPrimary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.background)
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
