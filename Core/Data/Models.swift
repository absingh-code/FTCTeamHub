import Foundation
import SwiftData

@Model
final class AppUser {
    @Attribute(.unique) var id: String
    var name: String
    var email: String
    var role: String          // "Software", "Hardware", "Strategy", "Scouter" — never "Lead"
    var profileImageURL: String?
    var googleToken: String?
    var isActive: Bool
    var lastSeen: Date?

    init(id: String, name: String, email: String, role: String = "Software",
         profileImageURL: String? = nil, googleToken: String? = nil,
         isActive: Bool = false, lastSeen: Date? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.profileImageURL = profileImageURL
        self.googleToken = googleToken
        self.isActive = isActive
        self.lastSeen = lastSeen
    }
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var assignedToID: String?
    var status: String        // "todo", "inProgress", "blocked", "done"
    var priority: String      // "low", "medium", "high"
    var deadline: Date?
    var tags: [String]
    var dateCreated: Date
    var notes: String?

    init(id: UUID = UUID(), title: String, assignedToID: String? = nil,
         status: String = "todo", priority: String = "medium",
         deadline: Date? = nil, tags: [String] = [], dateCreated: Date = .now,
         notes: String? = nil) {
        self.id = id
        self.title = title
        self.assignedToID = assignedToID
        self.status = status
        self.priority = priority
        self.deadline = deadline
        self.tags = tags
        self.dateCreated = dateCreated
        self.notes = notes
    }
}

@Model
final class NotebookEntry {
    @Attribute(.unique) var id: UUID
    var authorID: String
    var authorName: String
    var content: String
    var tags: [String]
    var hardwareConfigLinked: String?
    var timestamp: Date

    init(id: UUID = UUID(), authorID: String, authorName: String,
         content: String, tags: [String] = [], hardwareConfigLinked: String? = nil,
         timestamp: Date = .now) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.content = content
        self.tags = tags
        self.hardwareConfigLinked = hardwareConfigLinked
        self.timestamp = timestamp
    }
}

@Model
final class ScoutingRecord {
    @Attribute(.unique) var id: UUID
    var matchNumber: Int
    var teamScouted: Int
    var authorID: String
    var autoScore: Int
    var teleopScore: Int
    var notes: String
    var eventCode: String?
    var timestamp: Date

    init(id: UUID = UUID(), matchNumber: Int, teamScouted: Int, authorID: String,
         autoScore: Int = 0, teleopScore: Int = 0, notes: String = "",
         eventCode: String? = nil, timestamp: Date = .now) {
        self.id = id
        self.matchNumber = matchNumber
        self.teamScouted = teamScouted
        self.authorID = authorID
        self.autoScore = autoScore
        self.teleopScore = teleopScore
        self.notes = notes
        self.eventCode = eventCode
        self.timestamp = timestamp
    }
}

@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var authorID: String
    var upvotes: Int
    var comments: [String]
    var dateCreated: Date

    init(id: UUID = UUID(), title: String, body: String, authorID: String,
         upvotes: Int = 0, comments: [String] = [], dateCreated: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.authorID = authorID
        self.upvotes = upvotes
        self.comments = comments
        self.dateCreated = dateCreated
    }
}

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var quantity: Int
    var lowStockThreshold: Int
    var location: String
    var status: String        // "ok", "low", "maintenance"
    var lastChecked: Date?

    init(id: UUID = UUID(), name: String, quantity: Int = 0,
         lowStockThreshold: Int = 2, location: String = "", status: String = "ok",
         lastChecked: Date? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.lowStockThreshold = lowStockThreshold
        self.location = location
        self.status = status
        self.lastChecked = lastChecked
    }
}

@Model
final class TeamEventRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: Date
    var location: String
    var notes: String
    var readinessChecklist: [String]

    init(id: UUID = UUID(), name: String, date: Date, location: String = "",
         notes: String = "", readinessChecklist: [String] = []) {
        self.id = id
        self.name = name
        self.date = date
        self.location = location
        self.notes = notes
        self.readinessChecklist = readinessChecklist
    }
}
