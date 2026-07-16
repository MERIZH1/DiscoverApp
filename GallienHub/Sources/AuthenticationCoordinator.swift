import AuthenticationServices
import Combine
import UIKit

enum HubAuthenticationError: LocalizedError {
    case invalidCallback
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            "Die Anmeldung lieferte kein gültiges Einmal-Ticket."
        case .couldNotStart:
            "Der sichere Anmeldedialog konnte nicht geöffnet werden."
        }
    }
}

final class AuthenticationCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isAuthenticating = false
    private var session: ASWebAuthenticationSession?

    func start(completion: @escaping (Result<String, Error>) -> Void) {
        guard session == nil else { return }
        isAuthenticating = true

        let session = ASWebAuthenticationSession(
            url: HubEndpoint.authenticationURL,
            callbackURLScheme: "gallienhub"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                self?.session = nil
                self?.isAuthenticating = false

                if let error {
                    completion(.failure(error))
                    return
                }
                let code = callbackURL
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
                    .flatMap { components in
                        components.queryItems?.first(where: { $0.name == "code" })?.value
                    }
                guard let code, !code.isEmpty else {
                    completion(.failure(HubAuthenticationError.invalidCallback))
                    return
                }
                completion(.success(code))
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session

        if !session.start() {
            self.session = nil
            isAuthenticating = false
            completion(.failure(HubAuthenticationError.couldNotStart))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
            ?? ASPresentationAnchor()
    }
}

