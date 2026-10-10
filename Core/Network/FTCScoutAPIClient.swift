import Foundation

/// Real GraphQL client for api.ftcscout.org.
/// Surfaces errors honestly. Never fabricates data.
@Observable
final class FTCScoutAPIClient {
    var isLoading = false
    var errorMessage: String?
    var events: [FTCEventDTO] = []

    private let endpoint = URL(string: "https://api.ftcscout.org/graphql")!

    struct FTCEventDTO: Identifiable, Decodable {
        var id: String { code }
        let code: String
        let name: String
        let start: String?
        let end: String?
    }

    func refreshEvents(season: Int = 2025) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let query = """
        query {
          events(season: \(season)) {
            code
            name
            start
            end
          }
        }
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Server returned an error"
                return
            }
            // Minimal parse — expand with full GraphQL decoding in production
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let eventsArray = dataDict["events"] as? [[String: Any]] {
                events = eventsArray.compactMap { dict in
                    guard let code = dict["code"] as? String,
                          let name = dict["name"] as? String else { return nil }
                    return FTCEventDTO(
                        code: code,
                        name: name,
                        start: dict["start"] as? String,
                        end: dict["end"] as? String
                    )
                }
            } else {
                errorMessage = "Unexpected response format"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
