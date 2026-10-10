import Foundation

enum CSVExporter {
    static func export(records: [ScoutingRecord]) -> String {
        var lines = ["matchNumber,teamScouted,autoScore,teleopScore,notes,timestamp"]
        let formatter = ISO8601DateFormatter()
        for r in records {
            let notes = r.notes.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\(r.matchNumber),\(r.teamScouted),\(r.autoScore),\(r.teleopScore),\"\(notes)\",\(formatter.string(from: r.timestamp))")
        }
        return lines.joined(separator: "\n")
    }
}
