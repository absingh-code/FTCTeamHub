import Foundation
import SwiftData

enum SharedRecordKind: String, Codable {
    case task, note, idea, inventory, teamEvent, matchReport, pitReport, scoutAssignment, issue, checklistTemplate, checklistRun, matchPlan
}

struct SharedRecord: Codable {
    let kind: SharedRecordKind
    let key: String
    let author: String?
    let payload: Data

    var id: String { Self.id(kind, key) }
    static func id(_ kind: SharedRecordKind, _ key: String) -> String { "\(kind.rawValue):\(key)" }

    @MainActor
    static func capture(_ model: any PersistentModel, includeDrafts: Bool = false) throws -> Self? {
        switch model {
        case let row as TaskItem:
            return try make(.task, row.id.uuidString, nil, TaskItemPayload(row))
        case let row as NotebookEntry:
            return try make(.note, row.id.uuidString, row.authorID, NotebookEntryPayload(row))
        case let row as Idea:
            return try make(.idea, row.id.uuidString, row.authorID, IdeaPayload(row))
        case let row as InventoryItem:
            return try make(.inventory, row.id.uuidString, nil, InventoryItemPayload(row))
        case let row as TeamEventRecord:
            return try make(.teamEvent, row.id.uuidString, nil, TeamEventRecordPayload(row))
        case let row as MatchObservation:
            guard row.submittedAt != nil || includeDrafts else { return nil }
            return try make(.matchReport, row.identity, row.author, MatchObservationPayload(row))
        case let row as PitObservation:
            return try make(.pitReport, row.id.uuidString, row.author, PitObservationPayload(row))
        case let row as ScoutAssignment:
            return try make(.scoutAssignment, row.identity, row.author, ScoutAssignmentPayload(row))
        case let row as RobotIssue:
            return try make(.issue, row.id.uuidString, nil, RobotIssuePayload(row))
        case let row as ChecklistTemplate:
            return try make(.checklistTemplate, row.key, nil, ChecklistTemplatePayload(row))
        case let row as ChecklistRun:
            return try make(.checklistRun, row.id.uuidString, nil, ChecklistRunPayload(row))
        case let row as MatchPlan:
            return try make(.matchPlan, row.matchKey, nil, MatchPlanPayload(row))
        default: return nil
        }
    }

    private static func make<T: Encodable>(_ kind: SharedRecordKind, _ key: String, _ author: String?, _ value: T) throws -> Self {
        let payload = try JSONEncoder().encode(value)
        guard payload.count < 60_000, !key.isEmpty, !key.contains("/") else {
            throw WorkspaceError.message("This record is too large or has an invalid identifier.")
        }
        return Self(kind: kind, key: key, author: author, payload: payload)
    }

    @MainActor
    func apply(in context: ModelContext, deleted: Bool, preserveDraft: Bool = false) throws {
        let decoder = JSONDecoder()
        switch kind {
        case .task:
            let value = try decoder.decode(TaskItemPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .note:
            let value = try decoder.decode(NotebookEntryPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .idea:
            let value = try decoder.decode(IdeaPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .inventory:
            let value = try decoder.decode(InventoryItemPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .teamEvent:
            let value = try decoder.decode(TeamEventRecordPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .matchReport:
            let value = try decoder.decode(MatchObservationPayload.self, from: payload)
            if deleted { try value.remove(from: context) }
            else { try value.project(in: context, preserveDraft: preserveDraft) }
        case .pitReport:
            let value = try decoder.decode(PitObservationPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .scoutAssignment:
            let value = try decoder.decode(ScoutAssignmentPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .issue:
            let value = try decoder.decode(RobotIssuePayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .checklistTemplate:
            let value = try decoder.decode(ChecklistTemplatePayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .checklistRun:
            let value = try decoder.decode(ChecklistRunPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        case .matchPlan:
            let value = try decoder.decode(MatchPlanPayload.self, from: payload)
            if deleted { try value.remove(from: context) } else { try value.project(in: context) }
        }
    }
}

private struct TaskItemPayload: Codable {
    let id: UUID
    let title: String
    let assignedToID: String?
    let status: String
    let priority: String
    let deadline: Date?
    let tags: [String]
    let dateCreated: Date
    let notes: String?

    init(_ row: TaskItem) {
        id = row.id
        title = row.title
        assignedToID = row.assignedToID
        status = row.status
        priority = row.priority
        deadline = row.deadline
        tags = row.tags
        dateCreated = row.dateCreated
        notes = row.notes
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? TaskItem(id: id, title: title)
        row.title = title
        row.assignedToID = assignedToID
        row.status = status
        row.priority = priority
        row.deadline = deadline
        row.tags = tags
        row.dateCreated = dateCreated
        row.notes = notes
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct NotebookEntryPayload: Codable {
    let id: UUID
    let authorID: String
    let authorName: String
    let content: String
    let tags: [String]
    let hardwareConfigLinked: String?
    let timestamp: Date

    init(_ row: NotebookEntry) {
        id = row.id
        authorID = row.authorID
        authorName = row.authorName
        content = row.content
        tags = row.tags
        hardwareConfigLinked = row.hardwareConfigLinked
        timestamp = row.timestamp
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<NotebookEntry>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? NotebookEntry(id: id, authorID: authorID, authorName: authorName, content: content)
        row.authorID = authorID
        row.authorName = authorName
        row.content = content
        row.tags = tags
        row.hardwareConfigLinked = hardwareConfigLinked
        row.timestamp = timestamp
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<NotebookEntry>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct IdeaPayload: Codable {
    let id: UUID
    let title: String
    let body: String
    let authorID: String
    let upvotes: Int
    let comments: [String]
    let dateCreated: Date

    init(_ row: Idea) {
        id = row.id
        title = row.title
        body = row.body
        authorID = row.authorID
        upvotes = row.upvotes
        comments = row.comments
        dateCreated = row.dateCreated
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<Idea>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? Idea(id: id, title: title, body: body, authorID: authorID)
        row.title = title
        row.body = body
        row.authorID = authorID
        row.upvotes = upvotes
        row.comments = comments
        row.dateCreated = dateCreated
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<Idea>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct InventoryItemPayload: Codable {
    let id: UUID
    let name: String
    let quantity: Int
    let lowStockThreshold: Int
    let location: String
    let status: String
    let lastChecked: Date?

    init(_ row: InventoryItem) {
        id = row.id
        name = row.name
        quantity = row.quantity
        lowStockThreshold = row.lowStockThreshold
        location = row.location
        status = row.status
        lastChecked = row.lastChecked
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? InventoryItem(id: id, name: name)
        row.name = name
        row.quantity = quantity
        row.lowStockThreshold = lowStockThreshold
        row.location = location
        row.status = status
        row.lastChecked = lastChecked
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct TeamEventRecordPayload: Codable {
    let id: UUID
    let name: String
    let date: Date
    let location: String
    let notes: String
    let readinessChecklist: [String]

    init(_ row: TeamEventRecord) {
        id = row.id
        name = row.name
        date = row.date
        location = row.location
        notes = row.notes
        readinessChecklist = row.readinessChecklist
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<TeamEventRecord>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? TeamEventRecord(id: id, name: name, date: date)
        row.name = name
        row.date = date
        row.location = location
        row.notes = notes
        row.readinessChecklist = readinessChecklist
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<TeamEventRecord>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct MatchObservationPayload: Codable {
    let identity: String
    let matchKey: String
    let eventCode: String
    let season: Int
    let providerID: Int
    let matchLabel: String
    let team: Int
    let author: String
    let schemaVersion: Int
    let created: Date
    let updated: Date
    let submittedAt: Date?
    let autoHiveTips: Int?
    let teleopHiveTips: Int?
    let gardenPieces: Int?
    let flowerPlacements: Int?
    let autoLeave: String
    let autoPark: String
    let finalPark: String
    let stopped: String
    let autoNotes: String
    let teleopNotes: String
    let reliabilityNotes: String
    let notes: String

    init(_ row: MatchObservation) {
        identity = row.identity
        matchKey = row.matchKey
        eventCode = row.eventCode
        season = row.season
        providerID = row.providerID
        matchLabel = row.matchLabel
        team = row.team
        author = row.author
        schemaVersion = row.schemaVersion
        created = row.created
        updated = row.updated
        submittedAt = row.submittedAt
        autoHiveTips = row.autoHiveTips
        teleopHiveTips = row.teleopHiveTips
        gardenPieces = row.gardenPieces
        flowerPlacements = row.flowerPlacements
        autoLeave = row.autoLeave
        autoPark = row.autoPark
        finalPark = row.finalPark
        stopped = row.stopped
        autoNotes = row.autoNotes
        teleopNotes = row.teleopNotes
        reliabilityNotes = row.reliabilityNotes
        notes = row.notes
    }

    @MainActor
    func project(in context: ModelContext, preserveDraft: Bool) throws {
        let key = identity
        let existing = try context.fetch(FetchDescriptor<MatchObservation>(predicate: #Predicate { $0.identity == key })).first
        if preserveDraft, let existing, existing.submittedAt == nil { return }
        let row = existing ?? MatchObservation(remoteIdentity: identity, matchKey: matchKey, eventCode: eventCode, season: season, providerID: providerID, matchLabel: matchLabel, team: team, author: author, schemaVersion: schemaVersion, created: created, updated: updated, submittedAt: submittedAt, autoHiveTips: autoHiveTips, teleopHiveTips: teleopHiveTips, gardenPieces: gardenPieces, flowerPlacements: flowerPlacements, autoLeave: autoLeave, autoPark: autoPark, finalPark: finalPark, stopped: stopped, autoNotes: autoNotes, teleopNotes: teleopNotes, reliabilityNotes: reliabilityNotes, notes: notes)
        row.matchKey = matchKey
        row.eventCode = eventCode
        row.season = season
        row.providerID = providerID
        row.matchLabel = matchLabel
        row.team = team
        row.author = author
        row.schemaVersion = schemaVersion
        row.created = created
        row.updated = updated
        row.submittedAt = submittedAt
        row.autoHiveTips = autoHiveTips
        row.teleopHiveTips = teleopHiveTips
        row.gardenPieces = gardenPieces
        row.flowerPlacements = flowerPlacements
        row.autoLeave = autoLeave
        row.autoPark = autoPark
        row.finalPark = finalPark
        row.stopped = stopped
        row.autoNotes = autoNotes
        row.teleopNotes = teleopNotes
        row.reliabilityNotes = reliabilityNotes
        row.notes = notes
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = identity
        if let row = try context.fetch(FetchDescriptor<MatchObservation>(predicate: #Predicate { $0.identity == key })).first {
            context.delete(row)
        }
    }
}

private struct PitObservationPayload: Codable {
    let id: UUID
    let team: Int
    let season: Int
    let eventCode: String
    let author: String
    let created: Date
    let drivetrain: String
    let mechanisms: String
    let autonomous: String
    let startPositions: String
    let capabilities: String
    let dimensions: String
    let reliability: String
    let notes: String

    init(_ row: PitObservation) {
        id = row.id
        team = row.team
        season = row.season
        eventCode = row.eventCode
        author = row.author
        created = row.created
        drivetrain = row.drivetrain
        mechanisms = row.mechanisms
        autonomous = row.autonomous
        startPositions = row.startPositions
        capabilities = row.capabilities
        dimensions = row.dimensions
        reliability = row.reliability
        notes = row.notes
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<PitObservation>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? PitObservation(remoteId: id, team: team, season: season, eventCode: eventCode, author: author, created: created, drivetrain: drivetrain, mechanisms: mechanisms, autonomous: autonomous, startPositions: startPositions, capabilities: capabilities, dimensions: dimensions, reliability: reliability, notes: notes)
        row.team = team
        row.season = season
        row.eventCode = eventCode
        row.author = author
        row.created = created
        row.drivetrain = drivetrain
        row.mechanisms = mechanisms
        row.autonomous = autonomous
        row.startPositions = startPositions
        row.capabilities = capabilities
        row.dimensions = dimensions
        row.reliability = reliability
        row.notes = notes
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<PitObservation>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct ScoutAssignmentPayload: Codable {
    let identity: String
    let author: String
    let team: Int
    let matchKey: String
    let matchLabel: String
    let eventCode: String
    let scheduled: Date?

    init(_ row: ScoutAssignment) {
        identity = row.identity
        author = row.author
        team = row.team
        matchKey = row.matchKey
        matchLabel = row.matchLabel
        eventCode = row.eventCode
        scheduled = row.scheduled
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = identity
        let existing = try context.fetch(FetchDescriptor<ScoutAssignment>(predicate: #Predicate { $0.identity == key })).first
        let row = existing ?? ScoutAssignment(remoteIdentity: identity, author: author, team: team, matchKey: matchKey, matchLabel: matchLabel, eventCode: eventCode, scheduled: scheduled)
        row.author = author
        row.team = team
        row.matchKey = matchKey
        row.matchLabel = matchLabel
        row.eventCode = eventCode
        row.scheduled = scheduled
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = identity
        if let row = try context.fetch(FetchDescriptor<ScoutAssignment>(predicate: #Predicate { $0.identity == key })).first {
            context.delete(row)
        }
    }
}

private struct RobotIssuePayload: Codable {
    let id: UUID
    let title: String
    let detail: String
    let subsystem: String
    let severity: String
    let status: String
    let owner: String
    let created: Date
    let updated: Date
    let matchKey: String?
    let matchLabel: String?
    let resolution: String

    init(_ row: RobotIssue) {
        id = row.id
        title = row.title
        detail = row.detail
        subsystem = row.subsystem
        severity = row.severity
        status = row.status
        owner = row.owner
        created = row.created
        updated = row.updated
        matchKey = row.matchKey
        matchLabel = row.matchLabel
        resolution = row.resolution
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<RobotIssue>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? RobotIssue(remoteId: id, title: title, detail: detail, subsystem: subsystem, severity: severity, status: status, owner: owner, created: created, updated: updated, matchKey: matchKey, matchLabel: matchLabel, resolution: resolution)
        row.title = title
        row.detail = detail
        row.subsystem = subsystem
        row.severity = severity
        row.status = status
        row.owner = owner
        row.created = created
        row.updated = updated
        row.matchKey = matchKey
        row.matchLabel = matchLabel
        row.resolution = resolution
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<RobotIssue>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct ChecklistTemplatePayload: Codable {
    let key: String
    let title: String
    let items: [String]

    init(_ row: ChecklistTemplate) {
        key = row.key
        title = row.title
        items = row.items
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = key
        let existing = try context.fetch(FetchDescriptor<ChecklistTemplate>(predicate: #Predicate { $0.key == key })).first
        let row = existing ?? ChecklistTemplate(key: key, title: title, items: items)
        row.title = title
        row.items = items
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = key
        if let row = try context.fetch(FetchDescriptor<ChecklistTemplate>(predicate: #Predicate { $0.key == key })).first {
            context.delete(row)
        }
    }
}

private struct ChecklistRunPayload: Codable {
    let id: UUID
    let templateKey: String
    let title: String
    let items: [String]
    let completedIndices: [Int]
    let matchKey: String?
    let matchLabel: String?
    let eventID: String?
    let started: Date
    let completed: Date?
    let completedBy: String?

    init(_ row: ChecklistRun) {
        id = row.id
        templateKey = row.templateKey
        title = row.title
        items = row.items
        completedIndices = row.completedIndices
        matchKey = row.matchKey
        matchLabel = row.matchLabel
        eventID = row.eventID
        started = row.started
        completed = row.completed
        completedBy = row.completedBy
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = id
        let existing = try context.fetch(FetchDescriptor<ChecklistRun>(predicate: #Predicate { $0.id == key })).first
        let row = existing ?? ChecklistRun(remoteId: id, templateKey: templateKey, title: title, items: items, completedIndices: completedIndices, matchKey: matchKey, matchLabel: matchLabel, eventID: eventID, started: started, completed: completed, completedBy: completedBy)
        row.templateKey = templateKey
        row.title = title
        row.items = items
        row.completedIndices = completedIndices
        row.matchKey = matchKey
        row.matchLabel = matchLabel
        row.eventID = eventID
        row.started = started
        row.completed = completed
        row.completedBy = completedBy
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = id
        if let row = try context.fetch(FetchDescriptor<ChecklistRun>(predicate: #Predicate { $0.id == key })).first {
            context.delete(row)
        }
    }
}

private struct MatchPlanPayload: Codable {
    let matchKey: String
    let autonomous: String
    let strategy: String
    let reminders: String
    let updated: Date

    init(_ row: MatchPlan) {
        matchKey = row.matchKey
        autonomous = row.autonomous
        strategy = row.strategy
        reminders = row.reminders
        updated = row.updated
    }

    @MainActor
    func project(in context: ModelContext) throws {
        let key = matchKey
        let existing = try context.fetch(FetchDescriptor<MatchPlan>(predicate: #Predicate { $0.matchKey == key })).first
        let row = existing ?? MatchPlan(matchKey: matchKey, autonomous: autonomous, strategy: strategy, reminders: reminders)
        row.autonomous = autonomous
        row.strategy = strategy
        row.reminders = reminders
        row.updated = updated
        if existing == nil { context.insert(row) }
    }

    @MainActor
    func remove(from context: ModelContext) throws {
        let key = matchKey
        if let row = try context.fetch(FetchDescriptor<MatchPlan>(predicate: #Predicate { $0.matchKey == key })).first {
            context.delete(row)
        }
    }
}
