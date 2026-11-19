import Foundation
import SwiftData
import XCTest
@testable import FTCTeamHub

final class FTCTeamHubTests: XCTestCase {
    private let event = FTCEvent(season: 2026, code: "USNJSOM3", name: "Test meet", start: "2026-11-15",
                                 end: "2026-11-15", timezone: "America/New_York", location: nil, modifiedRules: nil)

    func testPartialMatchLeavesMissingFieldsUnknown() throws {
        let match = try decodeMatch("""
            {"eventSeason":2026,"eventCode":"USNJSOM3","id":10006,"hasBeenPlayed":false,"tournamentLevel":"Quals"}
            """)
        XCTAssertEqual(match.key.id, "2026:USNJSOM3:10006")
        XCTAssertEqual(match.label, "Qualification 6")
        XCTAssertFalse(match.isPlayed)
        XCTAssertNil(match.scheduledDate)
        XCTAssertNil(match.scores)
        XCTAssertEqual(match.teamNumbers, [])
    }

    func testPlayedZeroScoreIsDifferentFromMissingScore() throws {
        let match = try decodeMatch("""
            {"eventSeason":2026,"eventCode":"USNJSOM3","id":10006,"hasBeenPlayed":true,
             "scheduledStartTime":"2026-11-15T16:30:00.000Z","actualStartTime":"2026-11-15T16:32:00Z",
             "scores":{"red":{"totalPoints":0},"blue":null},
             "teams":[{"teamNumber":36611,"alliance":"Red","station":"One"},{"teamNumber":1,"alliance":"Blue","station":"NotOnField"}]}
            """)
        XCTAssertTrue(match.isPlayed)
        XCTAssertEqual(match.teamNumbers, [36611])
        XCTAssertEqual(match.scores?.red?.totalPoints, 0)
        XCTAssertNil(match.scores?.blue?.totalPoints)
        XCTAssertEqual(match.actualDate?.timeIntervalSince(try XCTUnwrap(match.scheduledDate)), 120)
    }

    func testFTCScoutCacheDeduplicatesAndSurvivesNetworkLoss() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoutStub.self]
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let client = FTCScoutAPIClient(session: URLSession(configuration: config), cacheDirectory: folder)
        ScoutStub.setBody("""
            [{"eventSeason":2026,"eventCode":"USNJSOM3","id":10006,"hasBeenPlayed":false}]
            """)

        async let first = client.matches(event: event, refresh: true)
        async let second = client.matches(event: event, refresh: true)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.value, b.value)
        XCTAssertEqual(ScoutStub.requests, 1)

        ScoutStub.setBody("{ \"message\": \"invalid schema\" }")
        let restoredClient = FTCScoutAPIClient(session: URLSession(configuration: config), cacheDirectory: folder)
        let cached = try await restoredClient.matches(event: event, refresh: true)
        XCTAssertTrue(cached.fallback)
        XCTAssertEqual(cached.value, a.value)
    }

    @MainActor
    func testDraftAndSubmissionReopenWithoutCreatingDuplicate() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("scout.store")
        let match = try decodeMatch("""
            {"eventSeason":2026,"eventCode":"USNJSOM3","id":10006,"tournamentLevel":"Quals"}
            """)
        let target = ScoutTarget(match: match, team: 36611)
        let key = match.key.entryID(team: 36611, author: "scout-a")

        do {
            let container = try WorkspaceStore.open(at: url)
            let draft = MatchObservation(target: target, author: "scout-a")
            XCTAssertFalse(draft.hasObservations)
            XCTAssertEqual(draft.schemaVersion, 1)
            draft.gardenPieces = 0
            XCTAssertTrue(draft.hasObservations)
            container.mainContext.insert(draft)
            try container.mainContext.save()
        }
        do {
            let container = try WorkspaceStore.open(at: url)
            let fetch = FetchDescriptor<MatchObservation>(predicate: #Predicate { $0.identity == key })
            let rows = try container.mainContext.fetch(fetch)
            XCTAssertEqual(rows.count, 1)
            let draft = try XCTUnwrap(rows.first)
            XCTAssertEqual(draft.gardenPieces, 0)
            XCTAssertNil(draft.autoHiveTips)
            XCTAssertNil(draft.submittedAt)
            XCTAssertNotEqual(key, match.key.entryID(team: 36611, author: "scout-b"))
            draft.submittedAt = .now
            try container.mainContext.save()
        }
        let container = try WorkspaceStore.open(at: url)
        let saved = try container.mainContext.fetch(FetchDescriptor<MatchObservation>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertNotNil(saved.first?.submittedAt)
    }

    @MainActor
    func testLegacyStoreRemainsReadableAndNeedsMatchingAuthor() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("legacy.store")
        let config = ModelConfiguration(schema: WorkspaceStore.legacy, url: url, cloudKitDatabase: .none)
        do {
            let db = try ModelContainer(for: WorkspaceStore.legacy, configurations: [config])
            db.mainContext.insert(ScoutingRecord(matchNumber: 6, teamScouted: 36611, authorID: "original", autoScore: 5))
            db.mainContext.insert(TaskItem(title: "Check the drivetrain"))
            try db.mainContext.save()
        }
        XCTAssertFalse(try WorkspaceStore.legacyBelongs(to: "different", configuration: config))
        XCTAssertTrue(try WorkspaceStore.legacyBelongs(to: "original", configuration: config))
        let upgraded = try WorkspaceStore.open(at: url)
        XCTAssertEqual(try upgraded.mainContext.fetch(FetchDescriptor<ScoutingRecord>()).first?.autoScore, 5)
        XCTAssertEqual(try upgraded.mainContext.fetch(FetchDescriptor<TaskItem>()).first?.title, "Check the drivetrain")
    }

    @MainActor
    func testChecklistProgressStaysWithOneRun() throws {
        let base = try XCTUnwrap(ChecklistDefinition.defaults.first { $0.id == "pre-match" })
        let first = try decodeMatch("""
            {"eventSeason":2026,"eventCode":"USNJSOM3","id":10006}
            """)
        let second = try decodeMatch("""
            {"eventSeason":2026,"eventCode":"USNJSOM3","id":10007}
            """)
        let a = ChecklistRun(template: base, eventID: event.id, match: first)
        let b = ChecklistRun(template: base, eventID: event.id, match: second)
        a.completedIndices = Array(base.items.indices)
        XCTAssertTrue(a.readyToComplete)
        XCTAssertFalse(b.readyToComplete)
        XCTAssertNotEqual(a.matchKey, b.matchKey)
    }

    func testCSVQuotesNewlinesAndFormulaPrefixes() {
        XCTAssertEqual(CSVExporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.escape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(CSVExporter.escape("line\nnext"), "\"line\nnext\"")
        XCTAssertEqual(CSVExporter.escape(" =1+1"), "\"' =1+1\"")
    }

    private func decodeMatch(_ json: String) throws -> FTCMatch {
        try JSONDecoder().decode(FTCMatch.self, from: Data(json.utf8))
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

private final class ScoutStub: URLProtocol {
    private static let lock = NSLock()
    private static var body = Data()
    private static var count = 0

    static var requests: Int { lock.withLock { count } }

    static func setBody(_ json: String) {
        lock.withLock {
            body = Data(json.utf8)
            count = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bytes = Self.lock.withLock {
            Self.count += 1
            return Self.body
        }
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: bytes)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
