import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LegacyArchive: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let bytes: Data

    init(bytes: Data) { self.bytes = bytes }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.bytes = bytes
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }

    @MainActor
    static func export(googleID: String) throws -> Self? {
        guard let archive = try WorkspaceStore.openOwnedArchive(googleID: googleID) else { return nil }
        let context = archive.mainContext
        func models<T: PersistentModel>(_ type: T.Type) throws -> [any PersistentModel] {
            try context.fetch(FetchDescriptor<T>()).map { $0 }
        }
        var rows: [any PersistentModel] = []
        rows.append(contentsOf: try models(TaskItem.self))
        rows.append(contentsOf: try models(NotebookEntry.self))
        rows.append(contentsOf: try models(Idea.self))
        rows.append(contentsOf: try models(InventoryItem.self))
        rows.append(contentsOf: try models(TeamEventRecord.self))
        if archive.schema.entities.contains(where: { $0.name == "MatchObservation" }) {
            rows.append(contentsOf: try models(MatchObservation.self))
            rows.append(contentsOf: try models(PitObservation.self))
            rows.append(contentsOf: try models(ScoutAssignment.self))
            rows.append(contentsOf: try models(RobotIssue.self))
            rows.append(contentsOf: try models(ChecklistTemplate.self))
            rows.append(contentsOf: try models(ChecklistRun.self))
            rows.append(contentsOf: try models(MatchPlan.self))
        }
        let records = try rows.compactMap { row -> [String: Any]? in
            guard let record = try SharedRecord.capture(row, includeDrafts: true) else { return nil }
            return ["kind": record.kind.rawValue, "key": record.key,
                    "data": try JSONSerialization.jsonObject(with: record.payload)]
        }
        let reports: [[String: Any]] = try context.fetch(FetchDescriptor<ScoutingRecord>()).map {
            ["id": $0.id.uuidString, "matchNumber": $0.matchNumber, "teamScouted": $0.teamScouted,
             "authorID": $0.authorID, "autoScore": $0.autoScore, "teleopScore": $0.teleopScore,
             "notes": $0.notes, "eventCode": $0.eventCode.map { $0 as Any } ?? NSNull(),
             "timestamp": $0.timestamp.timeIntervalSinceReferenceDate]
        }
        let contacts: [[String: String]] = try context.fetch(FetchDescriptor<AppUser>()).map {
            ["id": $0.id, "name": $0.name, "role": $0.role]
        }

        let payload: [String: Any] = [
            "format": 1, "dateEncoding": "seconds since 2001-01-01T00:00:00Z",
            "records": records, "legacyScouting": reports, "localContacts": contacts
        ]
        return Self(bytes: try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]))
    }
}
