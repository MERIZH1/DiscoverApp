import Foundation

enum HubEndpoint: String, CaseIterable, Identifiable {
    case tailscale
    case lan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tailscale: "Tailscale"
        case .lan: "Heimnetz"
        }
    }

    var subtitle: String {
        switch self {
        case .tailscale: "Sicher erreichbar – auch unterwegs"
        case .lan: "Direkt über 192.168.2.14"
        }
    }

    var baseURL: URL {
        switch self {
        case .tailscale:
            URL(string: "https://gallien.tail24f6af.ts.net:8443/")!
        case .lan:
            URL(string: "http://192.168.2.14:1111/")!
        }
    }

    static var authenticationURL: URL {
        URL(string: "https://gallien.tail24f6af.ts.net:8443/auth/mobile/start")!
    }

    static var updateVersionURL: URL {
        URL(string: "https://gallien.tail24f6af.ts.net:8443/download/version.json")!
    }

    static var installSignalURL: URL {
        URL(string: "https://gallien.tail24f6af.ts.net:8443/download/install-started.json")!
    }

    static func exchangeURL(for code: String) -> URL? {
        var parts = URLComponents(
            url: URL(string: "https://gallien.tail24f6af.ts.net:8443/auth/mobile/exchange")!,
            resolvingAgainstBaseURL: false
        )
        parts?.queryItems = [URLQueryItem(name: "code", value: code)]
        return parts?.url
    }
}

