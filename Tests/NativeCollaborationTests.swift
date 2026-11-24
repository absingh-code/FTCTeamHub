import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import SwiftData
import XCTest
@testable import FTCTeamHub

final class NativeCollaborationTests: XCTestCase {
    @MainActor
    func testNativeClientsShareRecordsAndReplayDurableOutbox() async throws {
        let endpoint = URL(string: "http://127.0.0.1:9099/")!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 2
        guard let (body, _) = try? await URLSession.shared.data(for: request),
              String(decoding: body, as: UTF8.self).localizedCaseInsensitiveContains("emulator") else {
            throw XCTSkip("The Firebase Authentication emulator is required for native collaboration.")
        }

        let sender = try await connect("native-sender")
        let scout = try await connect("native-scout")
        XCTAssertNotEqual(sender.uid, scout.uid)
        let access = TeamAccess(id: "native-fixture", name: "Wild Circuits simulator", number: 36611, role: "member")
        let first = try SharedWorkspace(db: sender.db, team: access, uid: sender.uid)
        let second = try SharedWorkspace(db: scout.db, team: access, uid: scout.uid)
        defer { first.stop(); second.stop() }
        second.openChat()
        try await until("Both workspaces loaded and the chat listener was ready") {
            first.recordsReady && second.recordsReady && second.messagesReady
        }

        let message = "Native test " + UUID().uuidString
        try first.enqueueMessage(message)
        try await until("Teammate received an acknowledged chat message") {
            second.messages.contains { $0.text == message && $0.sender == sender.uid && $0.delivery == .sent }
        }

        let task = TaskItem(title: "Native task " + UUID().uuidString, assignedToID: scout.uid)
        let taskID = task.id
        first.container.mainContext.insert(task)
        try first.save(first.container.mainContext)
        try await until("Teammate received the task") { try self.task(taskID, in: second)?.status == "todo" }

        try await scout.db.disableNetwork()
        try await until("Second device reported its offline state") { !second.online }
        let assigned = try XCTUnwrap(self.task(taskID, in: second))
        assigned.status = "done"
        try second.save(second.container.mainContext)
        XCTAssertTrue(second.pending.contains { $0.record?.key == taskID.uuidString })
        second.stop()

        let reopened = try SharedWorkspace(db: scout.db, team: access, uid: scout.uid)
        defer { reopened.stop() }
        XCTAssertTrue(reopened.pending.contains { $0.record?.key == taskID.uuidString })
        try await scout.db.enableNetwork()
        try await until("First device received the second device's restored update") {
            try self.task(taskID, in: first)?.status == "done" && reopened.pending.isEmpty
        }
    }

    @MainActor
    private func connect(_ name: String) async throws -> (uid: String, db: Firestore) {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "demo-ftcteamhub"
        options.apiKey = "demo-emulator-key"
        let instance = name + "-" + UUID().uuidString
        FirebaseApp.configure(name: instance, options: options)
        let app = try XCTUnwrap(FirebaseApp.app(name: instance))
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let claims = ["sub": name, "email": name + "@example.test", "email_verified": true, "name": name] as [String: Any]
        let token = String(decoding: try JSONSerialization.data(withJSONObject: claims), as: UTF8.self)
        let result = try await auth.signIn(with: GoogleAuthProvider.credential(withIDToken: token, accessToken: ""))
        XCTAssertTrue(result.user.isEmailVerified)
        let db = Firestore.firestore(app: app)
        db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        return (result.user.uid, db)
    }

    @MainActor
    private func task(_ id: UUID, in workspace: SharedWorkspace) throws -> TaskItem? {
        try workspace.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    @MainActor
    private func until(_ description: String, _ condition: () throws -> Bool) async throws {
        let limit = Date.now.addingTimeInterval(16)
        repeat {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        } while Date.now < limit
        XCTFail(description)
        throw CocoaError(.coderInvalidValue)
    }
}
