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

    static func open(at url: URL) throws -> ModelContainer {
        let config = ModelConfiguration(schema: current, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: current, configurations: [config])
    }

    static func sharedFolder(project: String, team: String, uid: String) throws -> URL {
        let scope = [project, uid, team].map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
            .appendingPathComponent("SharedWorkspaces-v1", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        return folder
    }

    static func openOwnedArchive(googleID: String) throws -> ModelContainer? {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        let digest = SHA256.hash(data: Data(googleID.utf8)).map { String(format: "%02x", $0) }.joined()
        let accountStore = support.appendingPathComponent("Workspaces", isDirectory: true)
            .appendingPathComponent(digest + ".store")
        if FileManager.default.fileExists(atPath: accountStore.path) {
            let config = ModelConfiguration(schema: current, url: accountStore, allowsSave: false, cloudKitDatabase: .none)
            return try ModelContainer(for: current, configurations: [config])
        }

        let original = ModelConfiguration(schema: legacy, allowsSave: false, cloudKitDatabase: .none)
        guard FileManager.default.fileExists(atPath: original.url.path) else { return nil }
        let owner = UserDefaults.standard.string(forKey: "legacyWorkspaceOwner")
        if owner == googleID {
            let config = ModelConfiguration(schema: current, url: original.url, allowsSave: false, cloudKitDatabase: .none)
            return try ModelContainer(for: current, configurations: [config])
        }
        guard owner == nil, try legacyBelongs(to: googleID, configuration: original) else { return nil }
        return try ModelContainer(for: legacy, configurations: [original])
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
