import AuthenticationServices
import SwiftUI

// Muss mit den Tokens in app/static/style.css uebereinstimmen, damit
// zwischen nativer Huelle und WebView keine Farbkante sichtbar wird.
private let hubBackground = Color(red: 0.039, green: 0.043, blue: 0.055)  // #0a0b0e  --bg
private let hubPanel = Color(red: 0.078, green: 0.086, blue: 0.106)       // #14161b  --panel
private let hubBorder = Color(red: 0.137, green: 0.153, blue: 0.184)      // #23272f  --line
private let hubBlue = Color(red: 0.357, green: 0.549, blue: 1.0)          // #5b8cff  --accent

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gallienHub.endpoint") private var endpointValue = HubEndpoint.tailscale.rawValue
    @StateObject private var web = HubWebViewModel()
    @StateObject private var authentication = AuthenticationCoordinator()
    @StateObject private var updater = HubAppUpdater()
    @ObservedObject private var notifications = HubNotificationCoordinator.shared
    @State private var authenticationError: String?

    private var endpoint: HubEndpoint {
        HubEndpoint(rawValue: endpointValue) ?? .tailscale
    }

    var body: some View {
        ZStack {
            hubBackground
                .ignoresSafeArea()

            HubWebView(model: web)
                .ignoresSafeArea(.container, edges: .bottom)

            if let message = web.errorMessage {
                ConnectionErrorView(message: message) {
                    web.reload()
                } useTailscale: {
                    select(.tailscale)
                } useLAN: {
                    select(.lan)
                }
                .transition(.opacity)
            }

            if authentication.isAuthenticating {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                ProgressView("Sichere Anmeldung …")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(hubPanel, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(hubBorder, lineWidth: 1)
                    }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if web.isOutsideHub {
                ExternalNavigationBar {
                    web.goBack()
                } home: {
                    web.goHome()
                }
            } else if web.isLoading {
                ProgressView()
                    .tint(hubBlue)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
            }
        }
        .overlay(alignment: .top) {
            if let authenticationError {
                ErrorToast(message: authenticationError) {
                    self.authenticationError = nil
                }
                .padding(.top, 10)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            web.authenticationHandler = startAuthentication
            let webModel = web
            notifications.openControlHandler = { [weak webModel] in
                webModel?.openControlCenter()
            }
            notifications.requestAuthorizationIfNeeded()
            notifications.scheduleBackgroundRefresh()
            web.loadIfNeeded(endpoint)
            Task { await updater.checkForUpdate() }
        }
        .onDisappear {
            notifications.openControlHandler = nil
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await notifications.refreshFromServer() }
                Task { await updater.checkForUpdate() }
            case .background:
                notifications.scheduleBackgroundRefresh()
                Task { await notifications.refreshFromServer() }
            default:
                break
            }
        }
    }

    private func select(_ endpoint: HubEndpoint) {
        endpointValue = endpoint.rawValue
        web.load(endpoint)
    }

    private func startAuthentication() {
        authenticationError = nil
        authentication.start { result in
            switch result {
            case .success(let code):
                guard let exchangeURL = HubEndpoint.exchangeURL(for: code) else {
                    authenticationError = "Das Anmeldeticket konnte nicht übernommen werden."
                    return
                }
                endpointValue = HubEndpoint.tailscale.rawValue
                web.loadAuthenticated(url: exchangeURL)
            case .failure(let error):
                if let sessionError = error as? ASWebAuthenticationSessionError,
                   sessionError.code == .canceledLogin {
                    return
                }
                authenticationError = error.localizedDescription
            }
        }
    }
}

private struct ExternalNavigationBar: View {
    let back: () -> Void
    let home: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Label("Zurück", systemImage: "chevron.left")
            }
            Spacer()
            Text("Server-App")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: home) {
                Image(systemName: "square.grid.2x2.fill")
                    .accessibilityLabel("Zurück zum Hub")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(hubPanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(hubBorder)
                .frame(height: 1)
        }
    }
}

private struct ConnectionErrorView: View {
    let message: String
    let retry: () -> Void
    let useTailscale: () -> Void
    let useLAN: () -> Void

    var body: some View {
        ZStack {
            hubBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "server.rack")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(hubBlue)
                    .frame(width: 82, height: 82)
                    .background(hubPanel, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(hubBorder, lineWidth: 1)
                    }

                VStack(spacing: 8) {
                    Text("Server nicht erreichbar")
                        .font(.title2.bold())
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Button("Erneut versuchen", action: retry)
                        .buttonStyle(PrimaryHubButtonStyle())
                    Button("Über Tailscale öffnen", action: useTailscale)
                        .buttonStyle(SecondaryHubButtonStyle())
                    Button("Im Heimnetz öffnen", action: useLAN)
                        .buttonStyle(SecondaryHubButtonStyle())
                }
                .frame(maxWidth: 360)
            }
            .padding(30)
        }
    }
}

private struct ErrorToast: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote.weight(.medium))
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
        }
        .padding(14)
        .background(hubPanel, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(hubBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}

private struct PrimaryHubButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(hubBlue, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct SecondaryHubButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                configuration.isPressed ? Color(red: 0.13, green: 0.16, blue: 0.2) : hubPanel,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(hubBorder, lineWidth: 1)
            }
    }
}

