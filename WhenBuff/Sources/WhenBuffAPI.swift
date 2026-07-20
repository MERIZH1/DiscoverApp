import Foundation

enum WhenBuffAPIError: LocalizedError {
    case unreachable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unreachable: return "Der WhenBuff-Server ist gerade nicht erreichbar."
        case .invalidResponse: return "Der WhenBuff-Server hat ungültige Daten geliefert."
        }
    }
}

enum WhenBuffAPI {
    private static let baseURLs = [
        URL(string: "https://gallien.tail24f6af.ts.net:8443/whenbuff")!,
        URL(string: "http://192.168.2.14:1112")!,
        URL(string: "http://100.112.51.72:1112")!,
    ]

    static func servers() async throws -> WhenBuffServerEnvelope {
        try await fetch("api/v1/servers", query: [])
    }

    static func bootstrap(server: String) async throws -> WhenBuffBootstrap {
        try await fetch(
            "api/v1/bootstrap",
            query: [URLQueryItem(name: "server", value: server)]
        )
    }

    static func events(server: String, after: Int) async throws -> WhenBuffEventEnvelope {
        try await fetch(
            "api/v1/events",
            query: [
                URLQueryItem(name: "server", value: server),
                URLQueryItem(name: "after", value: String(after)),
            ]
        )
    }

    private static func fetch<T: Decodable>(
        _ path: String,
        query: [URLQueryItem]
    ) async throws -> T {
        var reachedServer = false
        for baseURL in baseURLs {
            var components = URLComponents(
                url: baseURL.appendingPathComponent(path),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = query.isEmpty ? nil : query
            guard let url = components?.url else { continue }

            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 8
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("WhenBuff-iOS/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else { continue }
                reachedServer = true
                guard (200..<300).contains(response.statusCode) else { continue }
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw WhenBuffAPIError.invalidResponse
                }
            } catch let error as WhenBuffAPIError {
                throw error
            } catch {
                continue
            }
        }
        throw reachedServer ? WhenBuffAPIError.invalidResponse : WhenBuffAPIError.unreachable
    }
}
