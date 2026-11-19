import Foundation
import Network
import Observation

@MainActor
@Observable
final class CompetitionWorkspace {
    static let teamNumber = 36611
    static let seasons = Array((2019...2026).reversed())
    var season = 2026 {
        didSet {
            if oldValue != season {
                events = nil
                selected = nil
                eventError = nil
                detail = nil
            }
        }
    }
    private(set) var events: ScoutFeed<[FTCEvent]>?
    private(set) var eventError: String?
    private(set) var loadingEvents = false
    private(set) var selected: FTCEvent?
    private(set) var detail: EventDetail?
    private(set) var loadingDetail = false

    private(set) var connection = ConnectionState.checking
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let state: ConnectionState = path.status == .satisfied ? .available : .offline
            Task { @MainActor in self?.connection = state }
        }
        monitor.start(queue: DispatchQueue(label: "FTCScout.network"))
    }

    deinit { monitor.cancel() }

    private let api = FTCScoutAPIClient.shared
    private var eventRequest = UUID()
    private var detailRequest = UUID()

    struct EventDetail {
        var matches: ScoutFeed<[FTCMatch]>?
        var standings: ScoutFeed<[FTCParticipation]>?
        var names: ScoutFeed<[Int: String]>?
        var matchesError: String?
        var standingsError: String?
        var namesError: String?

        var directory: TeamDirectory { TeamDirectory(names: names?.value ?? [:]) }
        var hasError: Bool { matchesError != nil || standingsError != nil || namesError != nil }
        var hasCachedData: Bool {
            matches?.fallback == true || standings?.fallback == true || names?.fallback == true
        }
        var lastUpdated: Date? {
            [matches?.fetchedAt, standings?.fetchedAt, names?.fetchedAt].compactMap { $0 }.min()
        }
    }

    var upcomingMatch: FTCMatch? {
        detail?.matches?.value.filter { match in
            !match.isPlayed && match.actualDate == nil &&
            match.teamNumbers.contains(Self.teamNumber) &&
            (match.scheduledDate.map { $0 >= .now } ?? true)
        }
        .min { ($0.scheduledDate ?? .distantFuture, $0.id) < ($1.scheduledDate ?? .distantFuture, $1.id) }
    }

    func choose(_ event: FTCEvent) {
        guard event.id != selected?.id else { return }
        detail = nil
        selected = event
        UserDefaults.standard.set(event.id, forKey: "competition-selection-\(event.season)")
    }

    func loadEvents(refresh: Bool = false) async {
        let request = UUID()
        eventRequest = request
        let year = season
        loadingEvents = true
        eventError = nil
        defer { if eventRequest == request { loadingEvents = false } }

        do {
            let feed = try await api.events(team: Self.teamNumber, season: year, refresh: refresh)
            guard request == eventRequest, year == season else { return }
            events = feed
            if let matching = feed.value.first(where: { $0.id == selected?.id }) {
                selected = matching
            } else {
                let pref = UserDefaults.standard.string(forKey: "competition-selection-\(year)")
                let choice = feed.value.first { $0.id == pref }
                    ?? feed.value.first { $0.isCurrent }
                    ?? feed.value.first { ($0.firstDay ?? "") >= Date.now.formatted(.iso8601.year().month().day()) }
                    ?? feed.value.last
                if let choice {
                    choose(choice)
                } else {
                    selected = nil
                    detail = nil
                }
            }
        } catch {
            guard request == eventRequest, year == season else { return }
            eventError = error.localizedDescription
        }
    }

    func loadSelected(refresh: Bool = false) async {
        let request = UUID()
        detailRequest = request
        guard let event = selected else {
            loadingDetail = false
            return
        }
        loadingDetail = true
        defer { if detailRequest == request { loadingDetail = false } }

        async let matches = capture { try await self.api.matches(event: event, refresh: refresh) }
        async let standings = capture { try await self.api.standings(event: event, refresh: refresh) }
        async let names = capture { try await self.api.names(event: event, refresh: refresh) }

        let (matchResult, standingResult, nameResult) = await (matches, standings, names)
        guard request == detailRequest, selected?.id == event.id else { return }
        var snapshot = detail ?? EventDetail()
        switch matchResult {
        case .success(let feed): snapshot.matches = feed; snapshot.matchesError = nil
        case .failure(let error): snapshot.matchesError = error.localizedDescription
        }
        switch standingResult {
        case .success(let feed): snapshot.standings = feed; snapshot.standingsError = nil
        case .failure(let error): snapshot.standingsError = error.localizedDescription
        }
        switch nameResult {
        case .success(let feed): snapshot.names = feed; snapshot.namesError = nil
        case .failure(let error): snapshot.namesError = error.localizedDescription
        }
        detail = snapshot
    }

    private func capture<T: Sendable>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}
