import FirebaseFirestore
import Foundation
import SwiftData
import SwiftUI

enum WorkspaceError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

struct WorkspaceMessage: Identifiable, Equatable {
    let id: String
    let sender: String
    let text: String
    let link: String?
    let date: Date
    var delivery: Delivery = .sent

    enum Delivery: Equatable { case sending, sent, failed }
}

struct PendingWorkspaceWrite: Identifiable, Codable {
    let id: String
    let created: Date
    let record: SharedRecord?
    let prior: String?
    let deleted: Bool
    let text: String?
    let link: String?
    let announcement: Bool
    var failure: String?

    var collection: String { record != nil ? "records" : announcement ? "announcements" : "messages" }
    var documentID: String { record?.id ?? id }
    var label: String { record.map { $0.kind.title } ?? (announcement ? "Announcement" : "Message") }
}

@MainActor
@Observable
final class SharedWorkspace {
    let team: TeamAccess
    let uid: String
    let tenant: DocumentReference
    let container: ModelContainer

    private(set) var members: [AppUser] = []
    private(set) var announcements: [WorkspaceMessage] = []
    private(set) var pending: [PendingWorkspaceWrite] = []
    private(set) var syncError: String?
    private(set) var chatError: String?
    private(set) var online = false
    private(set) var recordsReady = false
    private(set) var historyAvailable = false
    private(set) var loadingHistory = false
    private(set) var messagesReady = false
    private(set) var votes: [String: Set<String>] = [:]
    private var liveMessages: [WorkspaceMessage] = []
    private var olderMessages: [WorkspaceMessage] = []
    private var lastPage: QueryDocumentSnapshot?
    private let pageSize = 40
    private let db: Firestore
    private let queueURL: URL
    private var revisions: [String: String] = [:]
    private var synchronized: [String: StoredRecord] = [:]
    private var listeners: [ListenerRegistration] = []
    private var messagesListener: ListenerRegistration?
    private var running = true
    private var flushing = false

    private struct StoredRecord {
        let record: SharedRecord
        let revision: String
        let deleted: Bool
    }

    var messages: [WorkspaceMessage] {
        var merged = Dictionary(olderMessages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for message in liveMessages { merged[message.id] = message }
        for item in pending where item.collection == "messages" && merged[item.id] == nil {
            if let text = item.text {
                merged[item.id] = WorkspaceMessage(id: item.id, sender: uid, text: text, link: item.link,
                    date: item.created, delivery: item.failure == nil ? .sending : .failed)
            }
        }
        return merged.values.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    init(db: Firestore, team: TeamAccess, uid: String) throws {
        self.db = db
        self.team = team
        self.uid = uid
        tenant = db.collection("workspaces").document(team.id)
        let folder = try WorkspaceStore.sharedFolder(project: db.app.options.projectID ?? "", team: team.id, uid: uid)
        container = try WorkspaceStore.open(at: folder.appendingPathComponent("workspace.store"))
        container.mainContext.autosaveEnabled = false
        queueURL = folder.appendingPathComponent("outbox.json")
        if FileManager.default.fileExists(atPath: queueURL.path) {
            pending = try JSONDecoder().decode([PendingWorkspaceWrite].self, from: Data(contentsOf: queueURL))
            for write in pending {
                try write.record?.apply(in: container.mainContext, deleted: write.deleted)
            }
            try container.mainContext.save()
        }
        start()
    }

    func stop() {
        running = false
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        closeChat()
    }

    func save(_ context: ModelContext) throws {
        let changed = context.insertedModelsArray + context.changedModelsArray
        let deleted = context.deletedModelsArray
        var writes: [String: (SharedRecord, Bool)] = [:]
        for item in changed {
            if let record = try SharedRecord.capture(item) { writes[record.id] = (record, false) }
        }
        for item in deleted {
            if let record = try SharedRecord.capture(item) { writes[record.id] = (record, true) }
        }
        guard writes.isEmpty == false else { try context.save(); return }
        guard running, team.canEdit else { throw WorkspaceError.message("Your team access is read-only.") }
        guard recordsReady else { throw WorkspaceError.message("Wait for the team records to load, then try again.") }

        let previous = pending
        let changes = writes.values.map { record, deleted in
            PendingWorkspaceWrite(id: UUID().uuidString, created: .now, record: record,
                                  prior: pending.last(where: { $0.record?.id == record.id })?.id ?? revisions[record.id],
                                  deleted: deleted, text: nil, link: nil, announcement: false)
        }
        try replaceQueue(previous + changes)
        do { try context.save() }
        catch {
            try replaceQueue(previous)
            throw error
        }
        flush()
    }

    func reportDelivery(_ identity: String) -> String {
        let id = SharedRecord.id(.matchReport, identity)
        if let write = pending.last(where: { $0.record?.id == id }) {
            return write.failure == nil ? "Waiting to sync" : "Needs attention"
        }
        return synchronized[id]?.deleted == false ? "Shared with team" : "Checking sync"
    }

    func enqueueMessage(_ input: String, announcement: Bool = false, link: String? = nil) throws {
        let text = input.trimmed
        guard running, team.canEdit, !announcement || team.canCoordinate else {
            throw WorkspaceError.message("Your role can’t post here.")
        }
        guard !text.isEmpty, text.count <= 4000,
              link.map({ $0.count <= 500 && WorkspaceLinks.links(in: $0).first?.absoluteString == $0 }) ?? true else {
            throw WorkspaceError.message("Enter a message up to 4,000 characters and a valid HTTPS link.")
        }
        let item = PendingWorkspaceWrite(id: UUID().uuidString, created: .now, record: nil,
                                         prior: nil, deleted: false, text: text, link: link, announcement: announcement)
        try replaceQueue(pending + [item])
        flush()
    }

    func retry(_ item: PendingWorkspaceWrite) throws {
        var next = pending
        guard let index = next.firstIndex(where: { $0.id == item.id }), next[index].failure != nil else { return }
        next[index].failure = nil
        try replaceQueue(next)
        flush()
    }

    func discard(_ item: PendingWorkspaceWrite) throws {
        guard let newest = pending.first(where: { $0.id == item.id }), newest.failure != nil else { return }
        let remaining = pending.filter { $0.documentID != item.documentID || $0.collection != item.collection }
        try replaceQueue(remaining)
        if let record = item.record {
            let server = synchronized[record.id]
            try (server?.record ?? record).apply(in: container.mainContext, deleted: server?.deleted ?? true)
            try container.mainContext.save()
        }
        flush()
    }

    func openChat() {
        guard running, messagesListener == nil else { return }
        chatError = nil
        messagesListener = messageQuery.limit(to: pageSize).addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.running, self.messagesListener != nil else { return }
                if error != nil {
                    self.chatError = "Couldn’t load the conversation. Try again."
                    self.closeChat()
                    return
                }
                guard let snapshot, !snapshot.metadata.isFromCache, !snapshot.metadata.hasPendingWrites else { return }
                self.messagesReady = true
                if self.olderMessages.isEmpty, self.lastPage == nil {
                    self.lastPage = snapshot.documents.last
                    self.historyAvailable = snapshot.documents.count == self.pageSize
                }
                let page = snapshot.documents.compactMap(Self.message)
                let pageIDs = Set(page.map(\.id))
                self.olderMessages += self.liveMessages.filter { !pageIDs.contains($0.id) }
                self.liveMessages = page
            }
        }
    }

    func closeChat() {
        messagesListener?.remove()
        messagesListener = nil
    }

    func loadEarlierMessages() async {
        guard running, !loadingHistory, let cursor = lastPage else { return }
        loadingHistory = true
        chatError = nil
        defer { loadingHistory = false }
        do {
            let page = try await messageQuery.start(afterDocument: cursor).limit(to: pageSize).getDocuments(source: .server)
            guard running else { return }
            olderMessages += page.documents.compactMap(Self.message)
            lastPage = page.documents.last
            historyAvailable = page.documents.count == pageSize
        } catch {
            chatError = "Couldn’t load older messages. Check your connection and retry."
        }
    }

    func invite(email: String, role: String) async throws {
        let normalized = email.trimmed.lowercased()
        guard running, team.canCoordinate, ["member", "scout", "viewer"].contains(role),
              normalized.count <= 254, normalized.range(of: #"^[^@/\s]+@[^@/\s]+\.[^@/\s]+$"#, options: .regularExpression) != nil else {
            throw WorkspaceError.message("Enter the teammate’s Google email and role.")
        }
        try await tenant.collection("invites").document(normalized).setData([
            "role": role, "active": true, "invitedBy": uid, "invitedAt": FieldValue.serverTimestamp()
        ])
    }

    func revoke(_ member: AppUser) async throws {
        try await tenant.collection("members").document(member.id).updateData(["active": false])
    }

    func toggleVote(idea: UUID) async throws {
        let key = idea.uuidString
        let doc = tenant.collection("votes").document(key + ":" + uid)
        try await doc.setData(["ideaID": key, "uid": uid, "active": !(votes[key]?.contains(uid) ?? false),
                               "updatedAt": FieldValue.serverTimestamp()])
    }

    func reconnect() {
        guard running else { return }
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        syncError = nil
        start()
    }

    private var messageQuery: Query {
        tenant.collection("messages").order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
    }

    private func start() {
        listeners.append(tenant.collection("records").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            Task { @MainActor in self?.receiveRecords(snap, error) }
        })
        listeners.append(tenant.collection("members").whereField("active", isEqualTo: true).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            Task { @MainActor in self?.receiveMembers(snap, error) }
        })
        listeners.append(tenant.collection("announcements").order(by: "createdAt", descending: true).limit(to: 10)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                Task { @MainActor in
                    guard let self, self.running else { return }
                    if error != nil { self.syncError = "Couldn’t update announcements." }
                    if let snap, !snap.metadata.isFromCache, !snap.metadata.hasPendingWrites {
                        self.announcements = snap.documents.compactMap(Self.message)
                    }
                }
            })
        listeners.append(tenant.collection("votes").whereField("active", isEqualTo: true).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            Task { @MainActor in
                guard let self, self.running else { return }
                if error != nil { self.syncError = "Couldn’t update votes." }
                guard let snap, !snap.metadata.isFromCache else { return }
                self.votes = snap.documents.reduce(into: [:]) { result, doc in
                    if let idea = doc.get("ideaID") as? String, let uid = doc.get("uid") as? String {
                        result[idea, default: []].insert(uid)
                    }
                }
            }
        })
    }

    private func receiveMembers(_ snapshot: QuerySnapshot?, _ error: Error?) {
        guard running else { return }
        if error != nil { syncError = "Couldn’t refresh the roster." }
        guard let snapshot, !snapshot.metadata.isFromCache else { return }
        let people = snapshot.documents.compactMap { doc -> AppUser? in
            guard let name = doc.get("name") as? String, let role = doc.get("role") as? String else { return nil }
            return AppUser(id: doc.documentID, name: name, email: "", role: role)
        }
        members = people.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func receiveRecords(_ snapshot: QuerySnapshot?, _ error: Error?) {
        guard running else { return }
        if error != nil {
            online = false
            syncError = "Couldn’t connect to the team records. Retry from Team."
        }
        guard let snapshot else { return }
        online = !snapshot.metadata.isFromCache
        guard online, !snapshot.metadata.hasPendingWrites else { return }

        let context = container.mainContext
        let pendingIDs = Set(pending.compactMap { $0.record?.id })
        var next = synchronized
        do {
            for doc in snapshot.documents {
                guard let kindValue = doc.get("kind") as? String, let kind = SharedRecordKind(rawValue: kindValue),
                      let key = doc.get("key") as? String, let data = doc.get("data") as? [String: Any],
                      let revision = doc.get("revision") as? String, let deleted = doc.get("deleted") as? Bool else { continue }
                let payload = try JSONSerialization.data(withJSONObject: data)
                let record = SharedRecord(kind: kind, key: key, author: doc.get("author") as? String, payload: payload)
                guard doc.documentID == record.id else { continue }
                if !pendingIDs.contains(record.id) && next[record.id]?.revision != revision {
                    try record.apply(in: context, deleted: deleted, preserveDraft: true)
                }
                next[record.id] = StoredRecord(record: record, revision: revision, deleted: deleted)
            }
            if context.hasChanges { try context.save() }
            synchronized = next
            revisions = next.mapValues(\.revision)
            recordsReady = true
            flush()
        } catch {
            context.rollback()
            syncError = "A team record couldn’t be read. Retry the sync from Team."
        }
    }

    private static func message(_ doc: QueryDocumentSnapshot) -> WorkspaceMessage? {
        guard let sender = doc.get("sender") as? String, let text = doc.get("text") as? String,
              let date = doc.get("createdAt") as? Timestamp else { return nil }
        return WorkspaceMessage(id: doc.documentID, sender: sender, text: text,
                                link: doc.get("link") as? String, date: date.dateValue())
    }

    private func replaceQueue(_ queue: [PendingWorkspaceWrite]) throws {
        let data = try JSONEncoder().encode(queue)
        try data.write(to: queueURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        pending = queue
    }

    private func flush() {
        guard running, online, recordsReady, !flushing else { return }
        flushing = true
        Task {
            defer { flushing = false }
            while running, online {
                let blocked = Set(pending.filter { $0.failure != nil }.map { $0.collection + "/" + $0.documentID })
                guard let write = pending.first(where: {
                    !blocked.contains($0.collection + "/" + $0.documentID)
                }) else { return }
                do {
                    try await send(write)
                    guard running else { return }
                    try replaceQueue(pending.filter { $0.id != write.id })
                } catch {
                    guard running else { return }
                    let code = (error as NSError).code
                    if code == 4 || code == 14 { return }
                    var next = pending
                    guard let index = next.firstIndex(where: { $0.id == write.id }) else { continue }
                    next[index].failure = (error as? WorkspaceError)?.localizedDescription
                        ?? "Team access or validation stopped this update."
                    do { try replaceQueue(next) }
                    catch {
                        syncError = "Couldn’t update the saved queue."
                        return
                    }
                }
            }
        }
    }

    private func send(_ write: PendingWorkspaceWrite) async throws {
        let doc = tenant.collection(write.collection).document(write.documentID)
        let existing = try await doc.getDocument(source: .server)
        guard running else { return }
        if let record = write.record {
            let cloudRevision = existing.get("revision") as? String
            if cloudRevision == write.id { return }
            guard cloudRevision == write.prior else {
                throw WorkspaceError.message("A teammate changed this record. Open Sync to review the pending edit.")
            }
            let data = try JSONSerialization.jsonObject(with: record.payload)
            try await doc.setData([
                "kind": record.kind.rawValue, "key": record.key,
                "author": record.author ?? uid, "actor": uid,
                "revision": write.id, "prior": write.prior ?? "",
                "deleted": write.deleted, "data": data, "updatedAt": FieldValue.serverTimestamp()
            ])
            revisions[record.id] = write.id
        } else if !existing.exists, let text = write.text {
            var data: [String: Any] = ["sender": uid, "text": text, "createdAt": FieldValue.serverTimestamp()]
            if let link = write.link { data["link"] = link }
            try await doc.setData(data)
        }
    }
}

enum TeamWorkspaceKey: EnvironmentKey {
    static let defaultValue: SharedWorkspace? = nil
}

extension EnvironmentValues {
    var teamWorkspace: SharedWorkspace? {
        get { self[TeamWorkspaceKey.self] }
        set { self[TeamWorkspaceKey.self] = newValue }
    }
}

@MainActor
func saveWorkspace(_ context: ModelContext, in workspace: SharedWorkspace?) throws {
    if let workspace { try workspace.save(context) }
    else { try context.save() }
}

extension SharedRecordKind {
    var title: String {
        switch self {
        case .task: "Task"
        case .note: "Notebook entry"
        case .idea: "Idea"
        case .inventory: "Inventory"
        case .teamEvent: "Team event"
        case .matchReport: "Match report"
        case .pitReport: "Pit report"
        case .scoutAssignment: "Scouting assignment"
        case .issue: "Robot issue"
        case .checklistTemplate: "Checklist template"
        case .checklistRun: "Checklist run"
        case .matchPlan: "Match plan"
        }
    }
}
