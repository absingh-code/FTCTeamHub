import Foundation

enum CSVExporter {
    private static let header = [
        "season", "event_code", "provider_match_id", "match", "team_number", "scout_id", "schema_version",
        "saved_at", "auto_leave", "auto_park", "auto_hive_tips", "teleop_hive_tips", "garden_pieces",
        "flower_placements", "final_park", "unexpected_stop", "auto_notes", "teleop_notes",
        "reliability_notes", "notes", "legacy_auto_score", "legacy_teleop_score"
    ]

    static func export(reports: [MatchObservation], legacy: [ScoutingRecord]) -> String {
        let time = ISO8601DateFormatter()
        let currentRows = reports.compactMap { report -> [String]? in
            guard let saved = report.submittedAt else { return nil }
            return [
                String(report.season), report.eventCode, String(report.providerID), report.matchLabel, String(report.team),
                report.author, String(report.schemaVersion), time.string(from: saved), observation(report.autoLeave),
                observation(report.autoPark), number(report.autoHiveTips), number(report.teleopHiveTips),
                number(report.gardenPieces), number(report.flowerPlacements), observation(report.finalPark),
                observation(report.stopped), report.autoNotes, report.teleopNotes, report.reliabilityNotes, report.notes, "", ""
            ]
        }
        let legacyRows = legacy.map { record in
            ["", record.eventCode ?? "", "", String(record.matchNumber), String(record.teamScouted), record.authorID,
             "legacy", time.string(from: record.timestamp), "", "", "", "", "", "", "", "", "", "", "",
             record.notes, String(record.autoScore), String(record.teleopScore)]
        }
        return ([header] + currentRows + legacyRows).map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ text: String) -> String {
        let leading = text.trimmed.first
        let dangerous = leading.map { "=+-@".contains($0) } == true ||
                        text.hasPrefix("\t") || text.hasPrefix("\r") || text.hasPrefix("\n")
        let safe = dangerous ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func observation(_ value: String) -> String {
        value == Seen.unknown.rawValue ? "" : value
    }

    private static func number(_ value: Int?) -> String {
        value.map { String($0) } ?? ""
    }
}
