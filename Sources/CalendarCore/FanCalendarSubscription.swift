import Foundation

/// Only public team identifiers are sent. There is no user account or email.
enum FanCalendarSubscription {
    static func request(teamKey: String) throws -> URLRequest {
        guard !teamKey.isEmpty, teamKey.count <= 16,
            teamKey.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 38 })
        else {
            throw FeedError.unresolvedSubscription
        }
        struct Payload: Encodable {
            let teamKeys: [String]
            let sports = ["cfb"]
            let alarms: [String: Int]
            let includeAllGames = false
            let includeSessions = false
        }
        var request = URLRequest(url: URL(string: "https://www.fancalendar.app/api/subscription/create")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Payload(teamKeys: [teamKey], alarms: ["cfb-\(teamKey)": 0]))
        return request
    }

    static func subscriptionURL(from data: Data) throws -> URL {
        struct Response: Decodable { let subscriptionUrl: URL }
        return try validated(JSONDecoder().decode(Response.self, from: data).subscriptionUrl)
    }

    static func validated(_ url: URL) throws -> URL {
        guard url.query == nil, url.fragment == nil else { throw FeedError.invalidURL }
        let url = try FeedURL.validated(url.absoluteString)
        guard ["fancalendar.app", "www.fancalendar.app"].contains(url.host ?? ""),
            url.path.range(of: #"^/api/subscription/[a-f0-9]{16}\.ics$"#, options: .regularExpression) != nil,
            url.query == nil, url.fragment == nil
        else { throw FeedError.invalidURL }
        return url
    }
}
