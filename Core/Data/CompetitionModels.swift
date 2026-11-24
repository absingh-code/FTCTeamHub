import Foundation
import SwiftData

struct MatchKey: Hashable, Sendable {
    let season: Int
    let eventCode: String
    let providerID: Int

    var id: String { "\(season):\(eventCode.uppercased()):\(providerID)" }

    func entryID(team: Int, author: String) -> String {
        "\(id):\(team):\(author)"
    }
}

struct ScoutTarget: Identifiable {
    let match: FTCMatch
    let team: Int

    var id: String { "\(match.key.id):\(team)" }
}

enum Seen: String, CaseIterable, Identifiable {
    case unknown = "Unobserved"
    case no = "No"
    case yes = "Yes"

    var id: Self { self }
}

@Model
final class MatchObservation {
    @Attribute(.unique) var identity: String
    var matchKey: String
    var eventCode: String
    var season: Int
    var providerID: Int
    var matchLabel: String
    var team: Int
    var author: String
    var schemaVersion: Int
    var created: Date
    var updated: Date
    var submittedAt: Date?
    var autoLeave = Seen.unknown.rawValue
    var autoPark = Seen.unknown.rawValue
    var autoHiveTips: Int?
    var teleopHiveTips: Int?
    var gardenPieces: Int?
    var flowerPlacements: Int?
    var finalPark = Seen.unknown.rawValue
    var stopped = Seen.unknown.rawValue
    var autoNotes = ""
    var teleopNotes = ""
    var reliabilityNotes = ""
    var notes = ""

    init(target: ScoutTarget, author: String) {
        let key = target.match.key
        identity = key.entryID(team: target.team, author: author)
        matchKey = key.id
        eventCode = key.eventCode
        season = key.season
        providerID = key.providerID
        matchLabel = target.match.label
        team = target.team
        self.author = author
        schemaVersion = key.season == 2026 ? 1 : 0
        let now = Date.now
        created = now
        updated = now
    }

    var hasObservations: Bool {
        [autoLeave, autoPark, finalPark, stopped].contains { $0 != Seen.unknown.rawValue } ||
        [autoHiveTips, teleopHiveTips, gardenPieces, flowerPlacements].contains { $0 != nil } ||
        [autoNotes, teleopNotes, reliabilityNotes, notes].contains { !$0.trimmed.isEmpty }
    }

    init(remoteIdentity identity: String, matchKey: String, eventCode: String, season: Int, providerID: Int, matchLabel: String, team: Int, author: String, schemaVersion: Int, created: Date, updated: Date, submittedAt: Date?, autoHiveTips: Int?, teleopHiveTips: Int?, gardenPieces: Int?, flowerPlacements: Int?, autoLeave: String, autoPark: String, finalPark: String, stopped: String, autoNotes: String, teleopNotes: String, reliabilityNotes: String, notes: String) {
        self.identity = identity
        self.matchKey = matchKey
        self.eventCode = eventCode
        self.season = season
        self.providerID = providerID
        self.matchLabel = matchLabel
        self.team = team
        self.author = author
        self.schemaVersion = schemaVersion
        self.created = created
        self.updated = updated
        self.submittedAt = submittedAt
        self.autoHiveTips = autoHiveTips
        self.teleopHiveTips = teleopHiveTips
        self.gardenPieces = gardenPieces
        self.flowerPlacements = flowerPlacements
        self.autoLeave = autoLeave
        self.autoPark = autoPark
        self.finalPark = finalPark
        self.stopped = stopped
        self.autoNotes = autoNotes
        self.teleopNotes = teleopNotes
        self.reliabilityNotes = reliabilityNotes
        self.notes = notes
    }

}

@Model
final class PitObservation {
    @Attribute(.unique) var id: UUID
    var team: Int
    var season: Int
    var eventCode: String
    var author: String
    var created: Date
    var drivetrain: String
    var mechanisms: String
    var autonomous: String
    var startPositions: String
    var capabilities: String
    var dimensions: String
    var reliability: String
    var notes: String

    init(team: Int, event: FTCEvent, author: String, drivetrain: String, mechanisms: String,
         autonomous: String, startPositions: String, capabilities: String, dimensions: String,
         reliability: String, notes: String) {
        id = UUID()
        self.team = team
        season = event.season
        eventCode = event.code
        self.author = author
        created = .now
        self.drivetrain = drivetrain
        self.mechanisms = mechanisms
        self.autonomous = autonomous
        self.startPositions = startPositions
        self.capabilities = capabilities
        self.dimensions = dimensions
        self.reliability = reliability
        self.notes = notes
    }

    var isComplete: Bool {
        !drivetrain.trimmed.isEmpty && !autonomous.trimmed.isEmpty && !reliability.trimmed.isEmpty
    }

    init(remoteId id: UUID, team: Int, season: Int, eventCode: String, author: String, created: Date, drivetrain: String, mechanisms: String, autonomous: String, startPositions: String, capabilities: String, dimensions: String, reliability: String, notes: String) {
        self.id = id
        self.team = team
        self.season = season
        self.eventCode = eventCode
        self.author = author
        self.created = created
        self.drivetrain = drivetrain
        self.mechanisms = mechanisms
        self.autonomous = autonomous
        self.startPositions = startPositions
        self.capabilities = capabilities
        self.dimensions = dimensions
        self.reliability = reliability
        self.notes = notes
    }

}

@Model
final class ScoutAssignment {
    @Attribute(.unique) var identity: String
    var author: String
    var team: Int
    var matchKey: String
    var matchLabel: String
    var eventCode: String
    var scheduled: Date?

    init(match: FTCMatch, team: Int, author: String) {
        identity = match.key.entryID(team: team, author: author)
        matchKey = match.key.id
        matchLabel = match.label
        eventCode = match.eventCode
        self.team = team
        self.author = author
        scheduled = match.scheduledDate
    }

    init(remoteIdentity identity: String, author: String, team: Int, matchKey: String, matchLabel: String, eventCode: String, scheduled: Date?) {
        self.identity = identity
        self.author = author
        self.team = team
        self.matchKey = matchKey
        self.matchLabel = matchLabel
        self.eventCode = eventCode
        self.scheduled = scheduled
    }

}

enum IssueSeverity: String, CaseIterable, Identifiable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case critical = "Critical"

    var id: Self { self }
}

enum IssueStatus: String, CaseIterable, Identifiable {
    case open = "Open"
    case inProgress = "In Progress"
    case verification = "Ready to Verify"
    case resolved = "Resolved"

    var id: Self { self }
}

enum RobotSubsystem: String, CaseIterable, Identifiable {
    case drivetrain = "Drivetrain"
    case intake = "Intake"
    case lift = "Lift"
    case scoring = "Scoring mechanism"
    case electrical = "Electrical"
    case software = "Software"
    case vision = "Vision"
    case other = "Other"

    var id: Self { self }
}

@Model
final class RobotIssue {
    @Attribute(.unique) var id: UUID
    var title: String
    var detail: String
    var subsystem: String
    var severity: String
    var status: String
    var owner: String
    var created: Date
    var updated: Date
    var matchKey: String?
    var matchLabel: String?
    var resolution: String

    init(title: String, detail: String, subsystem: RobotSubsystem, severity: IssueSeverity,
         status: IssueStatus, owner: String, match: FTCMatch?, resolution: String) {
        id = UUID()
        self.title = title
        self.detail = detail
        self.subsystem = subsystem.rawValue
        self.severity = severity.rawValue
        self.status = status.rawValue
        self.owner = owner
        let now = Date.now
        created = now
        updated = now
        matchKey = match?.key.id
        matchLabel = match?.label
        self.resolution = resolution
    }

    var isOpen: Bool { status != IssueStatus.resolved.rawValue }

    init(remoteId id: UUID, title: String, detail: String, subsystem: String, severity: String, status: String, owner: String, created: Date, updated: Date, matchKey: String?, matchLabel: String?, resolution: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.subsystem = subsystem
        self.severity = severity
        self.status = status
        self.owner = owner
        self.created = created
        self.updated = updated
        self.matchKey = matchKey
        self.matchLabel = matchLabel
        self.resolution = resolution
    }

}

@Model
final class ChecklistTemplate {
    @Attribute(.unique) var key: String
    var title: String
    var items: [String]

    init(key: String, title: String, items: [String]) {
        self.key = key
        self.title = title
        self.items = items
    }
}

@Model
final class ChecklistRun {
    @Attribute(.unique) var id: UUID
    var templateKey: String
    var title: String
    var items: [String]
    var completedIndices: [Int]
    var matchKey: String?
    var matchLabel: String?
    var eventID: String?
    var started: Date
    var completed: Date?
    var completedBy: String?

    init(template: ChecklistDefinition, eventID: String?, match: FTCMatch?) {
        id = UUID()
        templateKey = template.id
        title = template.title
        items = template.items
        completedIndices = []
        self.eventID = eventID
        matchKey = match?.key.id
        matchLabel = match?.label
        started = .now
    }

    var readyToComplete: Bool {
        !items.isEmpty && items.indices.allSatisfy { completedIndices.contains($0) }
    }

    init(remoteId id: UUID, templateKey: String, title: String, items: [String], completedIndices: [Int], matchKey: String?, matchLabel: String?, eventID: String?, started: Date, completed: Date?, completedBy: String?) {
        self.id = id
        self.templateKey = templateKey
        self.title = title
        self.items = items
        self.completedIndices = completedIndices
        self.matchKey = matchKey
        self.matchLabel = matchLabel
        self.eventID = eventID
        self.started = started
        self.completed = completed
        self.completedBy = completedBy
    }

}

struct ChecklistDefinition: Identifiable {
    let id: String
    let title: String
    let items: [String]

    static let defaults = [
        Self(id: "packing", title: "Pre-event packing", items: [
            "Charge robot batteries", "Pack spare fasteners and tools", "Pack controllers and charger"
        ]),
        Self(id: "pre-match", title: "Pre-match", items: [
            "Secure a charged battery", "Check connectors and fasteners", "Confirm starting configuration",
            "Select the planned autonomous routine", "Verify controllers and Driver Station"
        ]),
        Self(id: "post-match", title: "Post-match", items: [
            "Inspect mechanisms", "Check the battery and connectors", "Record any new robot issues"
        ]),
        Self(id: "end-of-day", title: "End-of-day", items: [
            "Power down the robot", "Charge batteries", "Log repairs for the next meeting"
        ])
    ]
}

@Model
final class MatchPlan {
    @Attribute(.unique) var matchKey: String
    var autonomous: String
    var strategy: String
    var reminders: String
    var updated: Date

    init(matchKey: String, autonomous: String, strategy: String, reminders: String) {
        self.matchKey = matchKey
        self.autonomous = autonomous
        self.strategy = strategy
        self.reminders = reminders
        updated = .now
    }
}
