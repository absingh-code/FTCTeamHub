import CryptoKit
import Foundation
import SwiftData

@MainActor
enum WorkspaceStore {
    static let legacy = Schema([
        AppUser.self, TaskItem.self, NotebookEntry.self, ScoutingRecord.self,
        Idea.self, InventoryItem.self, TeamEventRecord.self
    ])
    static let current = Schema([
        AppUser.self, TaskItem.self, NotebookEntry.self, ScoutingRecord.self,
        Idea.self, InventoryItem.self, TeamEventRecord.self, MatchObservation.self,
        PitObservation.self, ScoutAssignment.self, RobotIssue.self, ChecklistTemplate.self,
        ChecklistRun.self, MatchPlan.self
    ])

    static func open(for userID: String, local: Bool) throws -> ModelContainer {
        let legacyConfig = ModelConfiguration(schema: legacy, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        let prefs = UserDefaults.standard
        let ownerKey = "legacyWorkspaceOwner"
        let owner = prefs.string(forKey: ownerKey)

        if !local, owner == userID {
            return try open(at: legacyConfig.url)
        }

        if !local, owner == nil, FileManager.default.fileExists(atPath: legacyConfig.url.path),
           try legacyBelongs(to: userID, configuration: legacyConfig) {
            let migrated = try open(at: legacyConfig.url)
            prefs.set(userID, forKey: ownerKey)
            return migrated
        }

        let deviceFolder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: deviceFolder, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return try open(at: deviceFolder.appendingPathComponent(digest + ".store"))
    }

    private static func open(at url: URL) throws -> ModelContainer {
        let config = ModelConfiguration(schema: current, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: current, configurations: [config])
    }

    static func legacyBelongs(to userID: String, configuration: ModelConfiguration) throws -> Bool {
        let original = try ModelContainer(for: legacy, configurations: [configuration])
        let db = original.mainContext
        var authors = Set(try db.fetch(FetchDescriptor<NotebookEntry>()).map(\.authorID))
        authors.formUnion(try db.fetch(FetchDescriptor<ScoutingRecord>()).map(\.authorID))
        authors.formUnion(try db.fetch(FetchDescriptor<Idea>()).map(\.authorID))
        return authors == Set([userID])
    }
}
